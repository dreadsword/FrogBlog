//
//  AppDelegate.swift
//  FrogBlog
//
//  Created by Robert Dodson on 12/21/19.
//  Copyright © 2019 Robert Dodson. All rights reserved.
//

import Cocoa
import WebKit

import Ink


@NSApplicationMain
class AppDelegate: NSObject,
	NSApplicationDelegate,
	WKNavigationDelegate,
	NSOutlineViewDataSource,
	NSOutlineViewDelegate
{
    @IBOutlet var markdownTextView: NSTextView!
    @IBOutlet weak var webView: WKWebView!
    @IBOutlet weak var window: NSWindow!
    @IBOutlet var cssTextView: NSTextView!
    @IBOutlet var htmlTextView: NSTextView!
    @IBOutlet weak var articleTitle: NSTextField!
    @IBOutlet weak var articleAuthor: NSTextField!
    @IBOutlet var dateLabel: NSTextField!
    @IBOutlet var dateText: NSTextField!
    
    @IBOutlet var mainSplitView: NSSplitView!
    @IBOutlet var editSplitView: NSSplitView!
    @IBOutlet var outlineView: NSOutlineView!
    
    @IBOutlet var articleTabView: NSTabView!
    @IBOutlet var previewTabView: NSTabView!
    
    
    var toplevel          : [Any]?
    var blogsettingspanel : ServerSettingsPanel?
    var articleTimer      : Timer!
    var preview           : Preview
    var model             : Model!

    
    override init()
    {
        preview = Preview()
        preview.cleanPreviewDir()
    }

    
    func applicationDidFinishLaunching(_ aNotification: Notification)
    {
        //
        // Some UI set up
        //
        webView.navigationDelegate = self
        
        let font = NSFont.systemFont(ofSize: 17)

        cssTextView.font = font
        htmlTextView.font = font
        markdownTextView.font = font

        cssTextView.textColor = NSColor.black
        cssTextView.backgroundColor = NSColor.white
        htmlTextView.textColor = NSColor.black
        htmlTextView.backgroundColor = NSColor.white
        markdownTextView.textColor = NSColor.black
        markdownTextView.backgroundColor = NSColor.white

        mainSplitView.setPosition(200.0, ofDividerAt: 0)
        editSplitView.setPosition(700.0, ofDividerAt: 0)
        
        markdownTextView.isAutomaticQuoteSubstitutionEnabled = false;
        markdownTextView.isAutomaticDashSubstitutionEnabled = false;
        markdownTextView.isAutomaticTextReplacementEnabled = false;
        
        Utils.writeDebugMsgToFile(msg: "FrogBlog Starting Up", rewindfile: true)
        
      
        
        
        //
        // load blogs and etc
        //
        model = Model()
        do
        {
            try model.loadBlogsAndDocs()
        }
        catch
        {
            errmsg(msg:"Load blogs error: \(error)")
        }
        
    
        //
        // Add blogs and doc to toplevel data struct for the outlineview
        //
        toplevel = [Any]()
        toplevel?.append(model.blogs!)
        toplevel?.append(model.docs!)
        
        outlineView.dataSource = self
        outlineView.delegate = self


        //
        // set up notifications
        //
        NotificationCenter.default.addObserver(
               self,
               selector: #selector(self.controlTextDidEndEditing),
               name: NSControl.textDidEndEditingNotification,
               object: nil)

        NotificationCenter.default.addObserver(
                      self,
                      selector: #selector(self.controlTextDidEndEditing),
                      name: NSText.didEndEditingNotification,
                      object: nil)

        
        //
        // init the save article timer
        //
        articleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true, block:
        { (timer) in
            
            if self.model.currentArticle == nil || self.model.currentBlog == nil
            {
                return
            }
               
            self.articleFromUI()
            self.saveArticle(article:self.model.currentArticle)
        })
        
        //
        // Load up the outlineview
        //
        updateOutline(blog:nil)
    }
    
    
    //
    // IBActions
    //
    @IBAction func publishButtonAction(_ sender: Any) { publish()                   }
    @IBAction func toHTMLButtonAction(_ sender: Any)  { tohtml()                    }
    @IBAction func blogSettingsAction(_ sender: Any)  { editBlog(editDoneBlock: {}) }
    @IBAction func viewInBrowserAction(_ sender: Any) { viewinbrowser()             }
    @IBAction func deleteBlogAction(_ sender: Any)    { deleteblog()                }
    @IBAction func deleteArticleAction(_ sender: Any) { deletearticle()             }
    @IBAction func importBlogAction(_ sender: Any)    { importblog()                }
    @IBAction func exportBlogAction(_ sender: Any)    { exportblog()                }
    @IBAction func newBlogAction(_ sender: Any)       { newblog(newblog:Blog())     }
    @IBAction func insertImageAction(_ sender: Any)   { insertImage()               }
    @IBAction func newArticleAction(_ sender: Any)    { newarticle()                }
    @IBAction func publishAllAction(_ sender: Any)    { publishAllArticles()        }
    
    
    //
    // Methods
    //
    
    func tohtml()
    {
        if isArticleSelected() == false
        {
            return
        }

        dowebpreview()
    }
    
      
    func publishAllArticles()
    {
        if isBlogSelected() == false
        {
            return
        }
       
        let blog = model.currentBlog!
        
        Alert.showAlertInWindow(window: self.window,
        message: "Publish all articles in this blog? \(blog.nickname)",
        info: "Are you sure?",
        ok:
        {
            let alert = Alert.showProgressWindow(window: self.window, message: "Publishing all articles in blog: \(blog.nickname)...")
             
            do
            {
                try self.model.filterBlogSupportFiles(blog:blog)
                try Publish().sendAllArticles(blog:blog)
            }
            catch let err as Publish.PublishError
            {
                self.errmsg(msg: "Error publishing all articles: \(err.msg) - \(err.info) - \(err.blog)")
            }
            catch
            {
                self.errmsg(msg: "Error sending all articles: \(error)")
            }
            
            alert.window.sheetParent!.endSheet(alert.window, returnCode: .cancel)
        },
        cancel:
        {
        })
    }
    
    
    func publish()
    {
        if isBlogSelected() == false
        {
            return
        }

        if isArticleSelected() == false
        {
          return
        }

        let blog = model.currentBlog!
        let article = model.currentArticle!

       do
       {
            articleFromUI()
            supportFilesFromUI()
        
            saveArticle(article:article)
            try model.saveSupportFiles(blog:blog)
            try model.saveBlog(blog:blog)
       }
       catch
       {
           errmsg(msg:"Blog save error \(error), won't publish.")
           return
       }
       
       var images : [Image]
       
       do
       {
            images = try (model.loadImages(fromArticle:article) ?? [Image]())
       }
       catch
       {
           errmsg(msg:"Error loading article images: \(error), won't publish.")
           return
       }
      
       
       let alert = Alert.showProgressWindow(window: self.window, message: "Publishing: \(article.title)...")
        
       do
       {
            try model.filterBlogSupportFiles(blog:blog)
            markCurrentArticlePublished()

           try Publish().sendArticleAndSupportFiles(blog: blog, article: article, images: images)
           
           Alert.showAlertInWindow(window: self.window, message: "Article published", info: article.title, ok: {}, cancel:{})
       }
       catch let err as Publish.PublishError
       {
           errmsg(msg: "Error publishing: \(err.msg) - \(err.info) - \(err.blog)")
       }
       catch
       {
           errmsg(msg:"Error publishing: \(error)")
       }
       alert.window.sheetParent!.endSheet(alert.window, returnCode: .cancel)
       
       
       DispatchQueue.global(qos: .background).async
       {
           self.deleteUnusedImages(article:article)
       }
    }
    
    
    func deleteUnusedImages(article:Article)
    {
        do
        {
            let images = try model.loadImages(fromArticle: article) ?? [Image]()
          
          var imagenamedict = Dictionary<String, Any>()
          
          let pattern = #"!\[.*\]\(images/(.*)\)"#
          let regex = try NSRegularExpression(pattern: pattern, options: [])
          
          regex.enumerateMatches(in: article.markdowntext, options: [], range: NSMakeRange(0, article.markdowntext.utf16.count))
          { (match, _, stop) in
              guard let match = match else { return }
              let cap = match.range(at: 1)
              guard let caprang = Range(cap, in: article.markdowntext) else { return }
              let file = String(article.markdowntext[caprang])
              imagenamedict[file] = file
          }
          
          var images_to_delete_from_server = [Image]()
          for image in images
          {
              if imagenamedict[image.name] == nil
              {
                  Utils.writeDebugMsgToFile(msg:"Deleting unused image \(image.name) from article \(article.title)")
                  
                  try model.deleteImage(image:image)
                  images_to_delete_from_server.append(image)
              }
          }
          
          
          if images_to_delete_from_server.count > 0
          {
              do
              {
                  try Publish().deleteImagesFromServer(blog: article.blog, images:images_to_delete_from_server)
              }
              catch let err as Publish.PublishError
              {
                  Utils.writeDebugMsgToFile(msg:"Error deleting images from server: \(err.msg) - \(err.info) - \(err.blog)")
              }
          }
      }
      catch
      {
          Utils.writeDebugMsgToFile(msg:"Error deleting unused images: \(error)")
      }
    }
    
    
    func markCurrentArticlePublished()
    {
        model.currentArticle.markAsPublished()
        dateLabel.stringValue = "Published Date"
    }
    
    
    func dowebpreview()
    {
         preview.createPreviewHTMLFile(filename: model.currentArticle.title,
                                       htmltext: getpreviewhtmltext())
         
         do
         {
             let images = try model.loadImages(fromArticle: model.currentArticle) ?? [Image]()
             for image in images
             {
                 let imagefilepath = "\(self.preview.imagedir.path)/\(image.name)"
                 
                 if FileManager.default.fileExists(atPath: imagefilepath) == false
                 {
                     try image.imagedata.write(to: URL(fileURLWithPath: imagefilepath))
                 }
             }
             
             webView.loadFileURL(preview.previewdir.appendingPathComponent("\(model.currentArticle.title).html"),
                                            allowingReadAccessTo: preview.previewdir)
         }
         catch
         {
             Utils.writeDebugMsgToFile(msg:"preview load error:L \(error)")
         }
     }
     
    

    func articleFromUI()
    {
       model.currentArticle.title = articleTitle.stringValue
       model.currentArticle.author = articleAuthor.stringValue
       model.currentArticle.markdowntext = markdownTextView.string
    }
    
    
    func supportFilesFromUI()
    {
       model.currentBlog.css.filetext = cssTextView.string
       model.currentBlog.html.filetext = htmlTextView.string
    }
   
   
    func clearUI()
    {
       articleTitle.stringValue  = ""
       articleAuthor.stringValue = ""
       dateText.stringValue      = ""
       markdownTextView.string   = ""
       
       articleTitle.isEnabled      = false
       articleAuthor.isEnabled     = false
       markdownTextView.isEditable = false
    }
   
 
   func formatDateSmall(date:Date) -> String
   {
       let RFC3339DateFormatter = DateFormatter()
       RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
       RFC3339DateFormatter.dateFormat = "mm/dd/yy-hh:mm:ss"
       let thedatestring = RFC3339DateFormatter.string(from: date)

       return thedatestring
   }
 
       
    
    func getpreviewhtmltext() -> String
    {
       previewTabView.selectTabViewItem(at: 0)
       articleFromUI()
       
       let parser = MarkdownParser()
       let html = parser.html(from: model.currentArticle.markdowntext)
       let articledate = model.currentArticle.formatArticleDate()


       let css = cssTextView.string
       
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy"
        let year = RFC3339DateFormatter.string(from: Date())

       let header = """
       <html>
           <head>
               <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
               <meta name="generator" content="FrogBlog"/>
               <meta name="author" content="Rob Dodson" />
               <meta name="copyright" content="Copyright \(year) (model.currentArticle.author)" />
               <style type='text/css'>
               \(css)
               </style>
           </head>
           <body>
           <div id=\"article\">
       <span class=\"articletitle\">\(model.currentArticle.title)</span><br />
       <span class=\"articleauthor\">\(model.currentArticle.author)</span> - <span class=\"articledate\">\(articledate)</span><br />
       """
       
       let page = String(format: "%@\n%@</div></body>\n</html>\n",header,html)

       return page;
    }
    
    
    func viewinbrowser()
    {
        if isBlogSelected() == false
        {
            return
        }
        
        let blog = model.currentBlog!
        
        let urlstring = String.init(format: "%@",blog.address)
        guard let url = URL.init(string: urlstring) else { return }
        NSWorkspace.shared.open(url)
    }
    
    
    func editBlog(editDoneBlock: @escaping () -> Void)
    {
        if isBlogSelected() == false
        {
            return
        }
        
        let blog = model.currentBlog!
        
        //
        // Remember the Panel handle blogsettingspanel must be global!
        // Otherwise it goes out of scope and does not work.
        // (Only lost one full day on this).
        //
        blogsettingspanel = ServerSettingsPanel.init(blog: blog, window:NSApplication.shared.mainWindow!)
        blogsettingspanel?.show(doneBlock:
            { (returnedblog) in
                
                self.model.currentBlog = returnedblog
                self.setTitle();
                do
                {
                    try self.model.saveBlog(blog: self.model.currentBlog)
                }
                catch
                {
                    self.errmsg(msg:"Error saving blog: \(error)")
                }
                editDoneBlock()
                self.updateOutline(blog: nil)
        })
    }
    
    
    func setTitle()
    {
        if model.currentBlog != nil
        {
            self.window.title = String.init(format: "FrogBlog - %@", model.currentBlog.nickname)
        }
    }
    
    
    func controlTextDidEndEditing(_ obj: Notification)
    {
        if model.currentArticle == nil { return }

        if obj.object is NSTextField
        {
            let control = obj.object as! NSTextField

            if control == articleTitle || control == articleAuthor
            {
                articleFromUI()
                saveArticle(article:self.model.currentArticle)
            }
            else if control == dateText // User can override date by manually editing.
            {
                let dateFormatter = Utils.getDateFormatter()
                guard let newdate = dateFormatter.date(from:dateText.stringValue) else
                {
                    errmsg(msg: "Bad date")
                    return
                }
                 
                if model.currentArticle.published == true
                {
                    let olduuid = self.model.currentArticle.uuid
                    let path = self.model.currentArticle.makePathOnServer()
                    
                    do
                    {
                        try self.model.deleteArticleByUUID(uuid:olduuid)
                    }
                    catch
                    {
                        Utils.writeDebugMsgToFile(msg:"Error deleting old dated article")
                    }
                    
                    
                    DispatchQueue.global(qos: .background).async
                    {
                        do
                        {
                            Utils.writeDebugMsgToFile(msg:"Deleting article because date changed")
                            try Publish().deleteArticleFromServerByPath(blog: self.model.currentBlog, path:path)
                        }
                        catch
                        {
                            Utils.writeDebugMsgToFile(msg:"error deleting article with old date from server")
                        }
                    }
                }
                
                model.currentArticle.publisheddate = newdate
                model.currentArticle.userdate = true
                dateLabel.stringValue = "User Date"
                dateText.stringValue = model.currentArticle.formatArticleDate()
                saveArticle(article:self.model.currentArticle)
                
                errmsg(msg: "You changed the article date, don't forget to publish it again.")
            }
        }
        else if obj.object is NSTextView
        {
            let control = obj.object as! NSTextView

            if control == markdownTextView
            {
                articleFromUI()
                saveArticle(article:self.model.currentArticle)
            }
            else if control == cssTextView || control == htmlTextView
            {
                supportFilesFromUI()
                
                do
                {
                    try self.model.saveSupportFiles(blog:model.currentBlog)
                }
                catch let err as Model.ModelError
                {
                    errmsg(msg:"Error saving support files: \(err.localizedDescription)")
                }
                catch
                {
                    errmsg(msg: "Error saving support files: \(error)")
                }
            }
        }

        updateOutline(blog:model.currentBlog)
    }
       
    
    func deleteblog()
    {
        if isBlogSelected() == false
        {
            return
        }
        
        let blog = model.currentBlog!
        
        Alert.showAlertInWindow(window: self.window,
        message: "Delete blog \"\(blog.nickname)\" and all its articles?",
        info: "Are you sure?",
        ok:
        {
            let alert = Alert.showProgressWindow(window: self.window, message: "Deleting \(blog.nickname)...")
           
            do
            {
                try self.model.deleteBlog(blog:blog)
                
                self.updateOutline(blog:nil)
                self.clearUI()
                self.model.currentBlog = nil
            }
            catch
            {
                self.errmsg(msg:"Error deleting blog \(blog.nickname): \(error)")
            }
            
            alert.window.sheetParent!.endSheet(alert.window, returnCode: .cancel)
            Alert.showAlertInWindow(window: self.window, message: "Blog deleted", info:"", ok: {}, cancel: {})
        },
        cancel: {})
    }
    
    
    func deletearticle()
    {
       if isArticleSelected() == false
       {
               return
       }
       
       Alert.showAlertInWindow(window: self.window,
                               message: "Delete this article: \(model.currentArticle.title)?",
           info: "Are you sure?",
           ok:
           {
               let articlename = self.model.currentArticle.title
               let alert = Alert.showProgressWindow(window: self.window, message: "Deleting article: \"\(articlename)\"...")
               
               do
               {
                    try self.model.deleteArticle(article: self.model.currentArticle)
               }
               catch
               {
                   Utils.writeDebugMsgToFile(msg:"Error deleting article \(self.model.currentArticle.title): \(error)")
               }
            
                self.updateOutline(blog:self.model.currentBlog)
                self.clearUI()
                self.model.currentArticle = nil
            
               
               alert.window.sheetParent!.endSheet(alert.window, returnCode: .cancel)
               Alert.showAlertInWindow(window: self.window, message: "Article \"\(articlename)\" deleted.", info: "", ok: {}, cancel: {})
           },
           cancel: {})
    }
    
    
    func importblog()
    {
        Utils.pickfile(title: "Import Blog", folders: false, startfolder: "~/Desktop")
        { (filename) in
           
            do
            {
                let blog = try Blog.importFromFile(importfile: filename)
                if blog != nil
                {
                    self.newblog(newblog:blog!)
                    
                    if let newblog = self.model.currentBlog
                    {
                        do
                        {
                            if newblog.articles != nil
                            {
                                for article in newblog.articles
                                {
                                    self.saveArticle(article: article)
                                }
                            }

                            if newblog.css    != nil { try self.model.saveFile(file: newblog.css) }
                            if newblog.html   != nil { try self.model.saveFile(file: newblog.html) }
                            if newblog.engine != nil { try self.model.saveFile(file: newblog.engine) }
                        }
                        catch
                        {
                            self.errmsg(msg: "Error importing blog: \(error)")
                        }
                    }
                }
            }
            catch
            {
                Alert.showAlertInWindow(window: self.window, message: "Error importing blog", info: "", ok: {}, cancel: {})
            }
            
            self.updateOutline(blog:nil)
       }
    }

    
    func exportblog()
    {
       if isBlogSelected() == false
       {
           return
       }
       
       Utils.savefile(title: "Export Blog", folders: true, startfolder: "~/Desktop")
       { (path) in
        
            var filename : String
            if path.hasSuffix(".json") == false
            {
               filename = "\(path).json"
            }
            else
            {
                filename = path
            }
            
           self.model.currentBlog.exportToFile(saveArticles: true,
                                         exportfilename:filename)
           
           Alert.showAlertInWindow(window: self.window,
                                   message: "File exported to: \(filename)",
                                   info: "",
                                   ok: {},
                                   cancel: {})
        }
    }
 
    
    func isArticleSelected() -> Bool
    {
       if model.currentArticle == nil
       {
           Alert.showAlertInWindow(window: self.window, message: "Select an article first.", info: "", ok: {}, cancel: {})
       }

       return model.currentArticle != nil
    }
    
    
    func isBlogSelected() -> Bool
    {
        if model.currentBlog == nil
        {
            Alert.showAlertInWindow(window: self.window, message: "Select a blog first.", info: "", ok: {}, cancel: {})
        }
    
        return model.currentBlog != nil
    }
    
    
    func errmsg(msg:String)
    {
        Utils.writeDebugMsgToFile(msg:msg)

        Alert.showAlertInWindow(window: self.window,
                                message: msg,
            info: "",
            ok: {},
            cancel: {})
    }
   
    
    func newblog(newblog:Blog)
    {
        model.addABlog(blog: newblog)
        model.currentBlog = newblog
        
        editBlog(editDoneBlock:
        {
            do
            {
                try self.model.getSupportFilesFromBundle(blog: newblog)
                try self.model.saveBlog(blog: newblog)
            }
            catch
            {
                Utils.writeDebugMsgToFile(msg:"newblog: Error saving files blog files to database : \(error)")
                return
            }
            
            self.model.currentBlog = newblog
            self.updateOutline(blog:nil)
        })
    }
    
     
    func insertImage()
    {
        if isArticleSelected() == false
        {
            return
        }
        
        let article = model.currentArticle!
        
       Utils.pickfile(title: "Select an Image", folders: true, startfolder: "~/Desktop", filepicked:
       { (filepath) in
        
           let fileurl = URL.init(fileURLWithPath: filepath)
           guard var nsimage = NSImage.init(contentsOfFile: fileurl.path)
               else
           {
               Utils.writeDebugMsgToFile(msg:"Error loading image \(filepath)")
               Alert.showAlertInWindow(window: self.window, message: "Error loading image \(filepath)", info: "", ok: {}, cancel: {})
               return
           }
           
           nsimage = Utils.resizeImage(image: nsimage, minimumSize: 400.0)
           
           guard let imagedata = Utils.getImageData(imagename:fileurl.lastPathComponent,nsimage:nsimage)
               else
           {
               Utils.writeDebugMsgToFile(msg:"Error getting image data")
               Alert.showAlertInWindow(window: self.window, message: "Error getting image data", info: "from file: \(fileurl)", ok: {}, cancel: {})
               return
           }
           
           let image = Image(articleuuid:article.uuid, name: "\(article.title)-\(fileurl.lastPathComponent)", imagedata: imagedata)
           
           DispatchQueue.global(qos: .userInitiated).async
           {
               do
               {
                    try self.model.saveImage(image: image)
                    try imagedata.write(to: URL(fileURLWithPath: "\(self.preview.imagedir.path)/\(image.name)"))
               }
               catch
               {
                   Alert.showAlertInWindow(window: self.window, message: "Error save image: \(error)", info: "for file: \(fileurl)", ok: {}, cancel: {})
                   Utils.writeDebugMsgToFile(msg:"Error saving image: \(error)")
                   return
               }
           }
           
            let markdownimagetext = "\n![\(image.name)](images/\(image.name))\n"
            self.markdownTextView.string.append(markdownimagetext)
           
            self.saveArticle(article:article)
           
       })
   }
    
    
    func saveArticle(article:Article)
    {
        do
        {
            try model.saveArticle(article:article)
        }
        catch let err as Model.ModelError
        {
            errmsg(msg: "Error saving article \(article.title): \(err.localizedDescription)")
        }
        catch
        {
            errmsg(msg: "Error saving article \(article.title): \(error)")
        }
    }
    
    
    func newarticle()
    {
        if isBlogSelected() == false
        {
            return
        }
        
        let possibletitle = "Article Title"
        
        let article = Article(blog:model.currentBlog,title: possibletitle,
                              author: model.currentBlog.author,
                              bloguuid: model.currentBlog.uuid,
                              markdowntext: "Your article text here")
        
        editArticle(article: article)
        model.currentBlog.addArticle(newarticle: article)
        model.currentArticle = article
        
        do
        {
            saveArticle(article: article)
            try model.saveBlog(blog: model.currentBlog)
        }
        catch
        {
            errmsg(msg:"Error saving new article to database: \(error)")
        }
        
        updateOutline(blog:model.currentBlog)
    }
    
    
    func updateOutline(blog:Blog?)
    {
        if (blog != nil)
        {
            outlineView.reloadItem(blog, reloadChildren: true)
            outlineView.expandItem(blog)
        }
        else
        {
            outlineView.reloadItem(nil, reloadChildren: true)
            outlineView.expandItem(model.blogs)
        }
        
        outlineView.needsDisplay = true
    }


    func editArticle(article:Article)
    {
        model.currentBlog = article.blog
        
        articleTitle.isEnabled = true
        articleAuthor.isEnabled = true
        markdownTextView.isEditable = true
        
        cssTextView.string = article.blog.css.filetext
        htmlTextView.string = article.blog.html.filetext
        
        model.currentArticle = article
        articleTitle.stringValue = article.title
        articleAuthor.stringValue = article.author
        markdownTextView.string = article.markdowntext
        dateText.stringValue = model.currentArticle.formatArticleDate()
        
        if article.published == true
        {
            dateLabel.stringValue = "Published Date"
        }
        else
        {
            dateLabel.stringValue = "Date"
        }
        
        dowebpreview()
    }
    
    
    func popUpWindow(doc:Doc)
    {
        if doc.filename.starts(with: "http")
        {
            let browserwin = BrowserWindow(doc: doc)
            browserwin.show()
        }
        else if doc.filename.starts(with: "file:")
        {
            // markdown file?
        }
        else
        {
            let docwin = DocWindow(doc: doc)
            docwin.show()
        }
    }

    
    //
    // NSSApplication delegate methods
    //
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    {
        return false
    }

    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
    {
        if (flag)
        {
            return false
        }
        else
        {
            self.window.makeKeyAndOrderFront(self)
            return true
        }
    }

    
    func applicationWillTerminate(_ aNotification: Notification)
    {

    }


    //
    // OutlineView data source ----------
    //
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int
    {
        if item is Blog
        {
            let blog = item as? Blog
            return blog?.articles.count ?? 0
        }
        else if item is [Blog]
        {
            return model.blogs?.count ?? 0
        }
        else if item is [Doc]
        {
            return model.docs?.count ?? 0
        }
        else
        {
            return toplevel?.count ?? 0
        }
        
    }
    

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any
    {
       if item is Blog
       {
            let blog = item as? Blog
            return blog?.articles[index] as Any
       }
       else if item is Article
       {
            let article = item as? Article
            return article as Any
       }
       else if item is [Blog]
       {
            return model.blogs?[index] as Any
       }
        else if item is [Doc]
        {
            return model.docs?[index] as Any
        }
       else
       {
            return toplevel?[index] as Any
       }
    }

    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool
    {
        if item is Blog
        {
            return true
        }
        else if item is [Blog]
        {
            return true
        }
        else if item is [Any]
        {
            return true
        }
        else
        {
            return false
        }
    }
    //
    // OutlineView data source ----------
    //
    
    //
    // NSOutlineViewDelegate ----------
    //
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView?
    {
        let view = NSTextField()
        view.drawsBackground = false
        view.isBordered = false
        view.isEditable = false
        
        if item is Blog
        {
            let blog = item as? Blog
            view.stringValue = blog?.nickname ?? "blog nick"
            if model.currentBlog != nil && blog?.nickname == model.currentBlog.nickname
            {
                view.textColor = NSColor.controlAccentColor;
            }
        }
        else if item is Article
        {
            let article = item as! Article
            let name = String.init(format: "%@",article.title) // add date?
            view.stringValue = name
            
            if model.currentArticle != nil && article.uuid == model.currentArticle.uuid
            {
                view.textColor = NSColor.controlAccentColor;
            }
        }
        else if item is Doc
        {
            let doc = item as! Doc
            view.stringValue = doc.name
        }
        else if item is [Blog]
        {
            view.stringValue = "Blogs"
        }
        else if item is [Doc]
        {
            view.stringValue = "Help"
        }
        else
        {
            view.stringValue = "err"
        }
        
        return view
    }

    func outlineViewSelectionDidChange(_ notification: Notification)
    {
        let item = outlineView.item(atRow: outlineView.selectedRow)
        
        if item is Blog
        {
            model.currentBlog = (item as? Blog)!
        }
        else if item is Article
        {
            editArticle(article:(item as? Article)!)
        }
        else if item is Doc
        {
            popUpWindow(doc:(item as? Doc)!)
        }
        
        updateOutline(blog: nil)
        setTitle()
    }
    //
    // NSOutlineViewDelegate ----------
    //
}

