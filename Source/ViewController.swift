import Cocoa
import MetalKit

var vc:ViewController! = nil
var g = Graphics()
var win3D:NSWindowController! = nil
var cBuffer:MTLBuffer! = nil

let functionNames = [ "Linear", "Sinusoidal", "Spherical", "Swirl", "Horseshoe", "Polar",
                   "Hankerchief", "Heart", "Disc", "Spiral", "Hyperbolic", "Diamond", "Ex",
                   "Julia", "JuliaN", "Bent", "Waves", "Fisheye", "Popcorn", "Power", "Rings", "Fan",
                   "Eyefish", "Bubble", "Cylinder", "Tangent", "Cross", "Noise", "Blur", "Square" ]

class ViewController: NSViewController, NSWindowDelegate, WGDelegate {
    var shadowFlag:Bool = false
    var autoMoveFlag:Bool = false
    var control = Control()
    var threadGroupCount = MTLSize()
    var threadGroups = MTLSize()
    var texture1: MTLTexture!
    var texture2: MTLTexture!
    var pipeline:[MTLComputePipelineState] = []
    let queue = DispatchQueue(label:"Q")
    var offset3D = float3()
    
    lazy var device2D: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device2D.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device2D.makeCommandQueue() }()
    
    @IBOutlet var wg: WidgetGroup!
    @IBOutlet var metalTextureViewL: MetalTextureView!
    
    let PIPELINE_FRACTAL = 0
    let PIPELINE_SHADOW  = 1
    let shaderNames = [ "fractalShader","shadowShader" ]

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        wg.delegate = self
        
        cBuffer = device2D.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options:MTLResourceOptions.storageModeShared)
        
        let defaultLibrary:MTLLibrary! = device2D.makeDefaultLibrary()
        
        //------------------------------
        func loadShader(_ name:String) -> MTLComputePipelineState {
            do {
                guard let fn = defaultLibrary.makeFunction(name: name)  else { print("shader not found: " + name); exit(0) }
                return try device2D.makeComputePipelineState(function: fn)
            }
            catch { print("pipeline failure for : " + name); exit(0) }
        }
        
        for i in 0 ..< shaderNames.count { pipeline.append(loadShader(shaderNames[i])) }
        //------------------------------
        
        let w = pipeline[PIPELINE_FRACTAL].threadExecutionWidth
        let h = pipeline[PIPELINE_FRACTAL].maxTotalThreadsPerThreadgroup / w
        threadGroupCount = MTLSizeMake(w, h, 1)
        
        setControlPointer(&control)
        control.win3DFlag = 0
        controlRandom()
        initializeWidgetGroup()
        layoutViews()
        
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
    }
    
    override func viewDidAppear() {
        view.window?.delegate = self    // so we receive window size changed notifications
        resizeIfNecessary()
        dvrCount = 1 // resize metalview without delay
        
        wgCommand(.loadNext)
    }
    
    func windowWillClose(_ aNotification: Notification) {
        if let w = win3D { w.close() }
    }
    
    func win3DClosed() {
        win3D = nil
        control.win3DFlag = 0
        wg.refresh()
        updateImage() // to erase bounding box
    }
    
    //MARK: -
    
    func resizeIfNecessary() {
        let minWinSize:CGSize = CGSize(width:700, height:710)
        var r:CGRect = (view.window?.frame)!
        var needSizing:Bool = false
        
        if r.size.width  < minWinSize.width  { r.size.width = minWinSize.width; needSizing = true }
        if r.size.height < minWinSize.height { r.size.height = minWinSize.height; needSizing = true }
        
        if needSizing {
            view.window?.setFrame(r, display: true)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        reset()
        resizeIfNecessary()
        resetDelayedViewResizing()
    }
    
    //MARK: -
    
    var dvrCount:Int = 0
    
    // don't realloc metalTextures until they have finished resizing the window
    func resetDelayedViewResizing() {
        dvrCount = 10 // 20 = 1 second delay
    }
    
    //MARK: -
    
    var zoomValue:Float = 0
    var panX:Float = 0
    var panY:Float = 0
    var radialInUse:Bool = false
    
    func checkWhetherRadialAngleChanged() {
        let current:Bool = control.radialAngle > 0
        if current != radialInUse {
            radialInUse = current
            initializeWidgetGroup()
        }
    }
    
    @objc func timerHandler() {
        var refreshNeeded:Bool = wg.update()
        
        if autoMoveFlag {
            controlAutoMove();
            refreshNeeded = true
        }
        
        if zoomValue != 0 || panX != 0 || panY != 0 || offset3D.x != 0 || offset3D.y != 0 || offset3D.z != 0 { refreshNeeded = true }
        
        if refreshNeeded { updateImage() }
        
        if dvrCount > 0 {
            dvrCount -= 1
            if dvrCount <= 0 {
                layoutViews()
            }
        }
        
        checkWhetherRadialAngleChanged()
    }
    
    //MARK: -
    
    func reset() {
        if let w = win3D { w.close() }

        offset3D = float3()
        zoomValue = 0
        panX = 0
        panY = 0
        
        control.power = 2
        control.xmin = -2
        control.xmax = 1
        control.ymin = -1.5
        control.ymax = 1.5
        control.skip = 20
        control.stripeDensity = -1.343
        control.escapeRadius = 4
        control.multiplier = -0.381
        control.color = float3(0,0.4,0.7)
        control.maxIter = 200
        control.contrast = 4        
        control.height = 0.1
        
        updateImage()
        wg.hotKey("M")
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        wg.reset()
        wg.addCommand("E","Edit Grammar",.grammar)
        wg.addCommand("N","Rnd Grammar",.gRandom)
        wg.addString("Gstring",.gString)
        
        func fGroup(_ i:Int32) {
            let fList:[WgIdent] = [ .f1, .f2, .f3, .f4 ]
            let ident:WgIdent = fList[Int(i)]
            let pMin:Float = -3
            let pMax:Float = +3
            let pChg:Float = 0.025
            let sMin:Float = 0.1
            let sMax:Float = +4
            let sChg:Float = 0.025
            
            wg.addLine()
            wg.addColor(ident,Float(RowHT * 4))
            wg.addCommand((i+1).description, functionNames[Int(getEquationIndex(i))],ident)
            wg.addDualFloat("",funcXtPointer(i),funcYtPointer(i),pMin,pMax,pChg,"Translate")
            wg.addDualFloat("",funcXsPointer(i),funcYsPointer(i),sMin,sMax,sChg,"Scale")
            wg.addSingleFloat("",funcRotPointer(i),pMin,pMax,pChg, "Rotate")
        }
        
        for i:Int32 in 0 ..< 4 { fGroup(i) }
        
        wg.addLine()
        wg.addSingleFloat("M",&control.multiplier, -1,1,0.1, "Multiplier")
        wg.addSingleFloat("S",&control.stripeDensity, -10,10,2, "Stripe")
        wg.addSingleFloat("5",&control.escapeRadius, 0.01,80,3, "Escape")
        wg.addSingleFloat("6",&control.contrast, 0.1,5,0.5, "Contrast")
        wg.addTriplet("C",&control.color,0,1,0.1, "Color")
        wg.addLine()
        wg.addColoredCommand("W",.shadow,"Shadow")

        wg.addLine()
        wg.addColor(.win3D,Float(RowHT)*2)
        wg.addCommand("J","3D Window",.win3D)
        wg.addTriplet("K",&offset3D,-1,1,0.1, "3D ROI")

        wg.addLine()
        wg.addColor(.radial,Float(RowHT))
        wg.addSingleFloat("Y",&control.radialAngle,0,Float.pi/2,0.03, "RadialSym")

        wg.addLine()
        wg.addCommand("Q","Randomize",.random)
        wg.addColoredCommand("Z",.auto,"Auto")
        wg.addLine()
        wg.addCommand("L","Load Next",.loadNext)
        wg.addCommand("V","Save/Load",.saveLoad)
        wg.addCommand("H","Help",.help)
        
        wg.addLine()
    }

    func toggle3DView() {
        control.win3DFlag = control.win3DFlag > 0 ? 0 : 1
        
        if control.win3DFlag > 0 {
            if win3D == nil {
                let mainStoryboard = NSStoryboard.init(name: NSStoryboard.Name("Main"), bundle: nil)
                win3D = mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Win3D")) as? NSWindowController
            }
            
            control.xmin3D = -1.60189855
            control.xmax3D = -0.976436495
            control.ymin3D = -0.20827961
            control.ymax3D = 0.235990882
            win3D.showWindow(self)
        }
        else {
            if win3D != nil { win3D.close() }
        }
        
        updateImage()
    }
    
    //MARK: -
    
    func grammarString() -> String {
        var chars:[UInt8] = []
        for i in 0 ..< MAX_GRAMMER { chars.append(UInt8(getGrammarCharacter(Int32(i)))) }
        chars.append(UInt8(0))
        
        return String(data:Data(chars), encoding: .utf8)!
    }
    
    func updateGrammarString() {
        initializeWidgetGroup()
        wg.refresh()
        updateImage()
    }
    
    //MARK: -
    
    func wgCommand(_ cmd: WgIdent) {
        func presentPopover(_ name:String) {
            let mvc = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
            let vc = mvc.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(name)) as! NSViewController
            self.present(vc, asPopoverRelativeTo: wg.bounds, of: wg, preferredEdge: .minX, behavior: .transient)
        }
        
        func equationPickerPopover(_ groupIndex:Int32) {
            funcGroupIndex = Int(groupIndex)
            equationIndex = Int(getEquationIndex(groupIndex))
            presentPopover("EquationPickerVC")
        }
        
        switch(cmd) {
        case .f1 : equationPickerPopover(0)
        case .f2 : equationPickerPopover(1)
        case .f3 : equationPickerPopover(2)
        case .f4 : equationPickerPopover(3)
        case .grammar :
            presentPopover("GrammarViewVC")
        case .saveLoad :
            presentPopover("SaveLoadVC")
        case .help :
            helpIndex = 0
            presentPopover("HelpVC")
            
        case .reset : reset()
        case .auto :
            autoMoveFlag = !autoMoveFlag
            if autoMoveFlag { controlInitAutoMove() }
        case .gRandom :
            controlRandomGrammar()
            updateGrammarString()
        case .random :
            controlRandom()
            updateGrammarString()
        case .shadow :
            shadowFlag = !shadowFlag
            metalTextureViewL.initialize(shadowFlag ? texture2 : texture1)
            updateImage()
        case .loadNext :
            let ss = SaveLoadViewController()
            ss.loadNext()
            controlJustLoaded()
        case .win3D :
            toggle3DView()
        default : break
        }
        
        wg.refresh()
    }
    
    func wgToggle(_ ident:WgIdent) {
        switch(ident) {
        default : break
        }
        
        wg.refresh()
    }
    
    func wgGetString(_ ident:WgIdent) -> String {
        switch ident {
        case .gString : return grammarString()
        default : return "Zorro"
        }
    }
    
    func wgGetColor(_ ident:WgIdent) -> NSColor {
        var highlight:Bool = false
        switch(ident) {
        case .f1 : highlight = isFunctionActive(0) > 0
        case .f2 : highlight = isFunctionActive(1) > 0
        case .f3 : highlight = isFunctionActive(2) > 0
        case .f4 : highlight = isFunctionActive(3) > 0
        case .win3D : highlight = control.win3DFlag > 0
        case .shadow : highlight = shadowFlag
        case .auto :  highlight = autoMoveFlag
        case .radial : highlight = control.radialAngle > 0
        default : break
        }
        
        return highlight ? wgHighlightColor : wgBackgroundColor
    }
    
    func wgOptionSelected(_ ident: WgIdent, _ index: Int) {}
    func wgGetOptionString(_ ident: WgIdent) -> String { return "" }
    
    //MARK: -
    
    let WGWidth:CGFloat = 140
    
    func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height
        let xBase:CGFloat = wg.isHidden ? 0 : WGWidth
        
        if !wg.isHidden { wg.frame = CGRect(x:1, y:1, width:xBase-1, height:ys-2) }
        
        metalTextureViewL.frame = CGRect(x:xBase+1, y:1, width:xs-xBase-2, height:ys-2)
        
        setImageViewResolution()
        updateImage()
    }
    
    func controlJustLoaded() {
        control.win3DFlag = 0
        if win3D != nil {           // so loadNext() closes previous images' 3D view
            win3D.close()
            win3D = nil
        }
        
        initializeWidgetGroup()
        wg.refresh()
        setImageViewResolution()
        updateImage()
    }
    
    func setImageViewResolution() {
        control.xSize = Int32(metalTextureViewL.frame.width)
        control.ySize = Int32(metalTextureViewL.frame.height)
        let xsz = Int(control.xSize)
        let ysz = Int(control.ySize)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: xsz,
            height: ysz,
            mipmapped: false)
        
        texture1 = device2D.makeTexture(descriptor: textureDescriptor)!
        texture2 = device2D.makeTexture(descriptor: textureDescriptor)!
        
        metalTextureViewL.initialize(texture1)
        
        let xs = xsz/threadGroupCount.width + 1
        let ys = ysz/threadGroupCount.height + 1
        threadGroups = MTLSize(width:xs, height:ys, depth: 1)
    }
    
    //MARK: -
    
    func updateRegionsOfInterest() {
        // pan ----------------
        if panX != 0 || panY != 0 {
            let mx = (control.xmax - control.xmin) * panX / 100
            let my = -(control.ymax - control.ymin) * panY / 100
            control.xmin -= mx
            control.xmax -= mx
            control.ymin -= my
            control.ymax -= my
            panX = 0
            panY = 0
        }
        
        // zoom ---------------
        if zoomValue != 0 {
            let amount:Float = (1.0 - zoomValue)
            let xsize = (control.xmax - control.xmin) * amount
            let ysize = (control.ymax - control.ymin) * amount
            let xc = (control.xmin + control.xmax) / 2
            let yc = (control.ymin + control.ymax) / 2
            control.xmin = xc - xsize/2
            control.xmax = xc + xsize/2
            control.ymin = yc - ysize/2
            control.ymax = yc + ysize/2
            zoomValue = 0
        }
        
        // 3D pan, zoom --------------
        if offset3D != float3() {
            let dx:Float = offset3D.x * control.dx * 5
            let dy:Float = -offset3D.y * control.dy * 5
            control.xmin3D += dx; control.xmax3D += dx
            control.ymin3D += dy; control.ymax3D += dy
            
            if offset3D.z != 0 {
                let amount:Float = (1.0 - offset3D.z)
                var xsize = (control.xmax3D - control.xmin3D) * amount
                var ysize = (control.ymax3D - control.ymin3D) * amount
                let minSz:Float = 0.001
                if xsize < minSz { xsize = minSz }
                if ysize < minSz { ysize = minSz }
                let xc = (control.xmin3D + control.xmax3D) / 2
                let yc = (control.ymin3D + control.ymax3D) / 2
                control.xmin3D = xc - xsize/2
                control.xmax3D = xc + xsize/2
                control.ymin3D = yc - ysize/2
                control.ymax3D = yc + ysize/2
            }
            offset3D = float3()
        }
        
        control.dx = (control.xmax - control.xmin) / Float(control.xSize)
        control.dy = (control.ymax - control.ymin) / Float(control.ySize)
        control.dx3D = (control.xmax3D - control.xmin3D) / Float(SIZE3D)
        control.dy3D = (control.ymax3D - control.ymin3D) / Float(SIZE3D)
    }
    
    //MARK: -
    
    func calcFractal() {
        updateRegionsOfInterest()
        
        control.is3DWindow = 0
        
        cBuffer.contents().copyMemory(from: &control, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline[PIPELINE_FRACTAL])
        commandEncoder.setTexture(texture1, index: 0)
        // skip unused buffer 0
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 1)

        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if shadowFlag {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_SHADOW])
            commandEncoder.setTexture(texture1, index: 0)
            commandEncoder.setTexture(texture2, index: 1)
            commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            commandEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }
    
    //MARK: -
    
    func updateImage() {
        calcFractal()
        metalTextureViewL.display(metalTextureViewL.layer!)
        
        if win3D != nil && vc3D != nil {
            vc3D.calcFractal()
        }
    }
    
    //MARK: -
    
    func isOptionKeyDown() -> Bool { return optionKeyDown }
    func isShiftKeyDown() -> Bool { return shiftKeyDown }
    func isLetterAKeyDown() -> Bool { return letterAKeyDown }

    var shiftKeyDown:Bool = false
    var optionKeyDown:Bool = false
    var letterAKeyDown:Bool = false
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        
        updateModifierKeyFlags(event)
        
        switch event.keyCode {
        case 123:   // Left arrow
            wg.hopValue(-1,0)
            return
        case 124:   // Right arrow
            wg.hopValue(+1,0)
            return
        case 125:   // Down arrow
            wg.hopValue(0,-1)
            return
        case 126:   // Up arrow
            wg.hopValue(0,+1)
            return
        case 43 :   // '<'
            wg.moveFocus(-1)
            return
        case 47 :   // '>'
            wg.moveFocus(1)
            return
        case 53 :   // Esc
            NSApplication.shared.terminate(self)
        case 0 :    // A
            letterAKeyDown = true
        case 29 :   // 0
            wg.isHidden = !wg.isHidden
            layoutViews()
        default:
            break
        }
        
        let keyCode = event.charactersIgnoringModifiers!.uppercased()
        //print("KeyDown ",keyCode,event.keyCode)
        
        wg.hotKey(keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        
        wg.stopChanges()
        
        switch event.keyCode {
        case 0 :    // A
            letterAKeyDown = false
        default :
            break
        }        
    }
    
    //MARK: -
    
    func flippedYCoord(_ pt:NSPoint) -> NSPoint {
        var npt = pt
        npt.y = view.bounds.size.height - pt.y
        return npt
    }
    
    func updateModifierKeyFlags(_ ev:NSEvent) {
        let rv = ev.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        shiftKeyDown   = rv & (1 << 17) != 0
        optionKeyDown  = rv & (1 << 19) != 0
    }
    
    var pt = NSPoint()
    
    override func mouseDown(with event: NSEvent) {
        pt = flippedYCoord(event.locationInWindow)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateModifierKeyFlags(event)
        
        var npt = flippedYCoord(event.locationInWindow)
        npt.x -= pt.x
        npt.y -= pt.y
        wg.focusMovement(npt,1)
    }
    
    override func mouseUp(with event: NSEvent) {
        pt.x = 0
        pt.y = 0
        wg.focusMovement(pt,0)
    }
    
    //MARK: -
    
    enum Win3DState { case initial,move }
    
    func win3DMap(_ pt:NSPoint, _ state:Win3DState) {
        var pt = pt
        if !wg.isHidden { pt.x -= WGWidth }
        
        let c:float2 = float2(Float(control.xmin + control.dx * Float(pt.x)), Float(control.ymin + control.dy * Float(pt.y)))
        
        switch(state) {
        case .initial :
            control.xmin3D = c.x; control.xmax3D = c.x
            control.ymin3D = c.y; control.ymax3D = c.y
        case .move :
            if c.x < control.xmin3D { control.xmin3D = c.x }
            if c.x > control.xmax3D { control.xmax3D = c.x }
            if c.y < control.ymin3D { control.ymin3D = c.y }
            if c.y > control.ymax3D { control.ymax3D = c.y }
            updateImage()
            vc3D.calcFractal()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if control.win3DFlag > 0 {
            win3DMap(flippedYCoord(event.locationInWindow),.initial)
        }
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        if control.win3DFlag > 0 {
            win3DMap(flippedYCoord(event.locationInWindow),.move)
        }
    }
    
    //MARK: -
    
    override func scrollWheel(with event: NSEvent) {
        zoomValue = Float(event.deltaY/20)
    }
}

// ===============================================

class BaseNSView: NSView {
    override var acceptsFirstResponder: Bool { return true }
}
