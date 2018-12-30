import Cocoa

class GrammarViewController: NSViewController {
    var sList:[NSSegmentedControl]! = nil
    
    @IBOutlet var c1:NSSegmentedControl!
    @IBOutlet var c2:NSSegmentedControl!
    @IBOutlet var c3:NSSegmentedControl!
    @IBOutlet var c4:NSSegmentedControl!
    @IBOutlet var c5:NSSegmentedControl!
    @IBOutlet var c6:NSSegmentedControl!
    @IBOutlet var c7:NSSegmentedControl!
    @IBOutlet var c8:NSSegmentedControl!
    @IBOutlet var c9:NSSegmentedControl!
    @IBOutlet var cA:NSSegmentedControl!
    @IBOutlet var cB:NSSegmentedControl!
    @IBOutlet var cC:NSSegmentedControl!

    @IBAction func cChanged(_ sender: NSSegmentedControl) {
        let chr:Int8 = sender.selectedSegment == 4 ? Int8(0) : Int8(sender.selectedSegment + 49) // 49 = ASCII '1'
        setGrammarCharacter(Int32(sender.tag(forSegment:0)),chr)
        vc.updateGrammarString()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sList = [ c1,c2,c3,c4,c5,c6,c7,c8,c9,cA,cB,cC ]
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()

        for i in 0 ..< sList.count {
            var index = Int(getGrammarCharacter(Int32(i)))   // ASCII, or zero
            if index == 0 { index = 4 } else { index -= 49 } // string terminator = 'End', else remove ASCII offset
            sList[i].selectedSegment = index
        }
    }
}
