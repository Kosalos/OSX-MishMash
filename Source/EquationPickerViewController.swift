import Cocoa

var funcGroupIndex = Int()
var equationIndex = Int()

class EquationPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet var scrollView: NSScrollView!
    var tv:NSTableView! = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        tv = scrollView.documentView as? NSTableView
        tv.dataSource = self
        tv.delegate = self
        
        let iset:IndexSet = [ equationIndex ]
        tv.selectRowIndexes(iset, byExtendingSelection:false)
    }
    
    func numberOfSections(in tableView: NSTableView) -> Int { return 1 }
    func numberOfRows(in tableView: NSTableView) -> Int { return functionNames.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { return CGFloat(20) }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = NSTextField(string: functionNames[row])
        view.isEditable = false
        view.isBordered = false
        view.backgroundColor = .clear
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        setEquationIndex(Int32(funcGroupIndex), Int32(row))
        vc.controlJustLoaded()
        return true
    }
}
