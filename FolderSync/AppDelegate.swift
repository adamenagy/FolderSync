//
//  AppDelegate.swift
//  FolderSync
//
//  Created by Adam Nagy on 14/10/2014.
//  Copyright (c) 2014 Adam Nagy. All rights reserved.
//

import Cocoa

// Storing the synchronization data
// Which files got updated, which were the same, etc
class ActionLog {
  var label: NSTextField!
  var table: NSTableView!
  var actionLog: [Int] = [0, 0, 0, 0]
  var filesProcessed: NSMutableDictionary = NSMutableDictionary()

  enum ActionType {
    case Same, Error, Updated, New
    func simpleDescription() -> String {
        switch self {
        case .Same:
            return "Same"
        case .Error:
            return "Error"
        case .Updated:
            return "Updated"
        case .New:
            return "New"
        }
    }
    
    static let types = [Same, Error, Updated, New]
  }
  
  init(label: NSTextField, table: NSTableView) {
    self.label = label
    self.table = table
  }
  
  var count: Int {
    get {
      return filesProcessed.count
    }
  }
  
  func getInfo() -> String {
    var result: [String] = []
    
    for actionType in ActionType.types {
      result.append(actionType.simpleDescription() + ": " +
        actionLog[actionType.hashValue].description)
    }
    
    return join(" / ", result)
  }
  
  func logItem(action: ActionType, fileName: String) {
    actionLog[action.hashValue]++
    
    // UI modification should be on main thread
    dispatch_async(dispatch_get_main_queue()) {
      self.label.stringValue = self.getInfo()
      self.filesProcessed.setValue(
        action.simpleDescription(), forKey: fileName)
      self.table.reloadData()
    }
  }
}

// Storing content in the two NSTextFields for
// the two path we synchronize
class Serializer {
  var prefs = NSUserDefaults.standardUserDefaults()
  
  var folder1: NSTextField!
  var folder2: NSTextField!
  
  init (folder1: NSTextField, folder2: NSTextField) {
    self.folder1 = folder1
    self.folder2 = folder2
  }
  
  func save () {
    prefs.setObject(folder1.stringValue, forKey:"folder1")
    prefs.setObject(folder2.stringValue, forKey:"folder2")
    prefs.synchronize()
  }
  
  func restore() {
    var folder1Text: AnyObject? =
      NSUserDefaults.objectForKey(prefs)("folder1")
    if (folder1Text != nil) {
      folder1.stringValue = folder1Text! as String
    }
    
    var folder2Text: AnyObject? =
      NSUserDefaults.objectForKey(prefs)("folder2")
    if (folder2Text != nil) {
      folder2.stringValue = folder2Text! as String
    }
  }
}

class AppDelegate:
  NSViewController, NSApplicationDelegate, NSTableViewDataSource {
  
  @IBOutlet weak var window: NSWindow!
  
  // We need this for background processing
  private let queue =
    dispatch_queue_create("serial-worker", DISPATCH_QUEUE_SERIAL)
  
  // For storing application data
  var serializer: Serializer!
  
  // Logging the actions taken
  var log: ActionLog!
  
  func applicationDidFinishLaunching(aNotification: NSNotification?) {
    // Insert code here to initialize your application
    serializer = Serializer(folder1: folder1Text, folder2: folder2Text)
    serializer.restore()
    
    // Init logging
    log = ActionLog(label: infoLabel, table: filesTable)
  }
  
  func applicationWillTerminate(aNotification: NSNotification?) {
    // Insert code here to tear down your application
    serializer.save()
  }
  
  override func viewDidLoad() {
  
  }
  
  @IBOutlet weak var folder1Text: NSTextField!
  
  @IBAction func folder1Clicked(sender: AnyObject) {
    folder1Text.stringValue = getFilePath()
  }
  
  @IBOutlet weak var folder2Text: NSTextField!
  
  @IBAction func folder2Clicked(sender: AnyObject) {
    folder2Text.stringValue = getFilePath()
  }
  
  // Table related functions /////////////////////////////////////////
  
  @IBOutlet weak var filesTable: NSTableView!
  
  func numberOfRowsInTableView(tableView: NSTableView!) -> Int {
    if (log == nil) {
      return 0
    } else {
      return log.count
    }
  }
  
  func tableView(tableView: NSTableView!,
  objectValueForTableColumn tableColumn: NSTableColumn!,
  row: Int) -> AnyObject! {
    var keys: NSArray = self.log.filesProcessed.allKeys
    // This is set in the UI builder under:
    // Identity >> Restoration ID
    if tableColumn.identifier == "Action" {
      return self.log.filesProcessed.objectForKey(
        keys.objectAtIndex(row))
    } else {
      return keys.objectAtIndex(row)
    }
  }
  
  @IBOutlet weak var infoLabel: NSTextField!

  @IBOutlet weak var progressIndicator: NSProgressIndicator!
  
  ////////////////////////////////////////////////////////////////////
  
  func getFilePath() -> String {
    var openPanel = NSOpenPanel()
    openPanel.prompt = "Select folder"
    openPanel.worksWhenModal = true
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.resolvesAliases = true
    openPanel.title = "Select folder"
    openPanel.message = "Select folder"
    openPanel.runModal()
    var chosenfile = openPanel.URL
    if (chosenfile != nil)
    {
      var theFile = chosenfile!.path!
      return (theFile)
    }
    
    return ""
  }
  
  func processFiles(fm: NSFileManager,
  fileName1: String, fileName2: String) {
    var err: NSError?
    
    // Check if the same file exists in the other folder
    if (fm.fileExistsAtPath(fileName2)) {
      // Check which file is newer
      var att1: NSDictionary? =
        fm.attributesOfItemAtPath(fileName1, error: nil)
      var att2: NSDictionary? =
        fm.attributesOfItemAtPath(fileName2, error: nil)
      if (att1 == nil || att2 == nil) {
        // Nothing we can do here
        return
      }
      
      var date1: NSDate? =
        att1!.objectForKey("NSFileModificationDate") as NSDate?
      var date2: NSDate? =
        att2!.objectForKey("NSFileModificationDate") as NSDate?
      
      if (date1 == nil || date2 == nil) {
        // Nothing we can do here
        return
      }
      
      var res = date1?.compare(date2!)
      if (res == NSComparisonResult.OrderedAscending) {
        // If fileName2 is newer
        fm.removeItemAtPath(fileName1, error: &err)
        if (err != nil) {
          log.logItem(ActionLog.ActionType.Error, fileName: fileName1)
        }
        fm.copyItemAtPath(fileName2, toPath: fileName1, error: &err)
        if (err != nil) {
          log.logItem(ActionLog.ActionType.Error, fileName: fileName1)
        } else {
          log.logItem(ActionLog.ActionType.Updated, fileName: fileName1)
        }
      } else if (res == NSComparisonResult.OrderedDescending) {
        // If fileName1 is newer
        fm.removeItemAtPath(fileName2, error: &err)
        if (err != nil) {
          log.logItem(ActionLog.ActionType.Error, fileName: fileName2)
        }
        fm.copyItemAtPath(fileName1, toPath: fileName2, error: &err)
        if (err != nil) {
          log.logItem(ActionLog.ActionType.Error, fileName: fileName2)
        } else {
          log.logItem(ActionLog.ActionType.Updated, fileName: fileName2)
        }
      } else {
        log.logItem(ActionLog.ActionType.Same, fileName: fileName2)
      }
    } else {
      // If fileName2 does not exist
      fm.copyItemAtPath(fileName1, toPath: fileName2, error: &err)
      if (err != nil) {
        log.logItem(ActionLog.ActionType.Error, fileName: fileName2)
      } else {
        log.logItem(ActionLog.ActionType.New, fileName: fileName2)
      }
    }
  }
  
  
  @IBAction func syncClicked(sender: AnyObject) {
    // Initialize values
    log = ActionLog(label: infoLabel, table: filesTable)
    
    progressIndicator.startAnimation(nil)
    
    // Let's start processing in the background
    dispatch_async(queue) {
      var fm = NSFileManager.defaultManager()
      
      var folder1 = self.folder1Text.stringValue
      var folder2 = self.folder2Text.stringValue
      
      if (folder1 == nil) || (folder2 == nil) {
        return
      }
      
      var files1 = fm.contentsOfDirectoryAtPath(folder1, error: nil)
      var files2: [String]? =
        fm.contentsOfDirectoryAtPath(folder2, error: nil) as [String]?
      
      if (files1 == nil) || (files2 == nil) {
        return
      }
      
      // Iterate through content of first directory
      for file1 in files1! {
        var fileName = file1.lastPathComponent
        
        self.processFiles(fm,
          fileName1: folder1 + "/" + (file1 as String),
          fileName2: folder2 + "/" + fileName)
        
        // If the handled file is in the other folder
        // then remove it so that it won't be handled in the next cycle
        if let index = find(files2!, fileName) {
          files2!.removeAtIndex(index)
        }
      }
      
      // Iterate through content of second directory
      for file2 in files2! {
        var fileName = file2.lastPathComponent
        
        self.processFiles(fm,
          fileName1: folder2 + "/" + (file2 as String),
          fileName2: folder1 + "/" + fileName)
      }
      
      self.progressIndicator.stopAnimation(nil)
    }
  }
}

