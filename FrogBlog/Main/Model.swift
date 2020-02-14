//
//  Model.swift
//  FrogBlog
//
//  Created by Robert Dodson on 2/7/20.
//  Copyright © 2020 Robert Dodson. All rights reserved.
//

import Foundation


class Model
{
    var db                : SqliteDB!
    var blogs             : [Blog]?
    var docs              : [Doc]?
    var currentBlog       : Blog!
    var currentArticle    : Article!
    
    
    struct ModelError: Error
    {
        let msg  : String
    }
    
    
    init()
    {
    }
    
    func loadBlogsAndDocs() throws
    {
        //
        // Load blogs
        //
        do
        {
            db = SqliteDB()

            blogs = try db.loadBlogs()
            for blog in blogs!
            {
                try db.loadArticles(blog:blog)

                try db.loadFile(blog: blog, filename: File.INDEXHTML)
                try db.loadFile(blog: blog, filename: File.STYLESCSS)
                try db.loadFile(blog: blog, filename: File.BLOGENGINE)

                try getSupportFilesFromBundle(blog:blog)
            }
        }
        catch
        {
            throw ModelError(msg:"Load blogs error: \(error)")
        }
        
        

        //
        // Load doc files
        //
        docs = [Doc]()
        let markdownhelp  = Doc(name: "Markdown Help", filename: "MarkdownHelp.txt")
        let csscolorshelp = Doc(name: "CSS Colors", filename: "https://www.w3schools.com/cssref/css_colors.asp")
        let frogbloghelp  = Doc(name: "FrogBlog Help", filename: "FrogBlogHelp.txt")
        docs!.append(markdownhelp)
        docs!.append(csscolorshelp)
        docs!.append(frogbloghelp)
    }
    
    
    //
    // Delete an article.
    // Delete the images that it uses and delete it from its blog's list of articles.
    // Delete the article and it's images from the server.
    //
    func deleteArticle(article:Article) throws
    {
        do
        {
            let images = try self.db.loadImages(fromArticle: article)
            let blog = article.blog!
            
            try self.db.deleteArticle(article: article)
            blog.articles.removeAll(where: { $0.uuid == article.uuid } )

            if article.published == true
            {
                do
                {
                    let pub = Publish()
                    try pub.deleteArticleFromServer(blog: blog, article: article)
                    try pub.deleteImagesFromServer(blog: blog, images: images)
                }
                catch let err as Publish.PublishError
                {
                    throw ModelError(msg: "Error deleting article from server: \(err.msg) - \(err.info) - \(err.blog)")
                }
            }
        }
        catch
        {
            throw ModelError(msg:"Error deleting article \(article.title): \(error)")
        }
    }
    
    
    func addABlog(blog:Blog)
    {
       blogs!.append(blog)
    }
    
    
    func saveArticle(article:Article) throws
    {
        try db.updateArticle(article: article)
    }
    
    
    func saveBlog(blog:Blog) throws
    {
        try db.updateBlog(blog: blog)
    }
    
    
    func saveFile(file:File) throws
    {
        try db.updateFile(file:file)
    }
    
    
    func deleteArticleByUUID(uuid:UUID) throws
    {
        try db.deleteArticleByUUID(uuid:uuid)
    }
    
    
    func deleteImage(image:Image) throws
    {
       try db.deleteImage(image:image)
    }
    
    
    func saveImage(image:Image) throws
    {
        try self.db.updateImage(image: image)
    }
    
    
    func loadImages(fromArticle:Article) throws -> [Image]?
    {
        return try db.loadImages(fromArticle: fromArticle)
    }
    
    
    func deleteBlog(blog:Blog) throws
    {
        do
        {
            for article in blog.articles
            {
                try deleteArticle(article: article)
            }
            
            try db.deleteFile(file:blog.html)
            try db.deleteFile(file:blog.css)
            try db.deleteFile(file:blog.engine)
            
            try db.deleteBlog(blog:blog)
            
            blogs!.removeAll(where: {$0.nickname == blog.nickname})
            
            try Publish().deleteBlogFolderFromServer(blog:blog)
        }
        catch let err as Publish.PublishError
        {
            throw ModelError(msg:"Error deleting blog on server \(blog.nickname): \(err.localizedDescription)")
        }
        catch
        {
            throw ModelError(msg:"Error deleting blog \(blog.nickname): \(error)")
        }
    }
    
    
    //
    // for now we always send the sample files for indedx.html and blogengine.php
    //
    func filterBlogSupportFiles(blog:Blog) throws
    {
        blog.html.filteredtext = Utils.filterHtmlText(blog: blog, text:  blog.html.filetext)           

        let enginefilteredtext = try self.getSampleFile(blog: blog, filename: File.BLOGENGINE)
        { (filetext) -> String in
            return Utils.filterHtmlText(blog: blog, text: filetext)
        }
        blog.engine.filteredtext = enginefilteredtext


        blog.css.filteredtext = blog.css.filetext // nothing to fiter in css file
    }
    
    
    func getSupportFilesFromBundle(blog:Blog) throws
    {
        if blog.html == nil
        {
            let indexhtmltext = try self.getSampleFile(blog: blog, filename: File.INDEXHTML)
            { (filetext) -> String in
                return filetext
            } ?? "html file error"
            
            blog.html = File(bloguuid: blog.uuid, filename: File.INDEXHTML, filetext: indexhtmltext)
            
            try self.db.updateFile(file:blog.html)
        }
        
        if blog.css == nil
        {
            let csstext = try self.getSampleFile(blog: blog, filename: File.STYLESCSS)
            { (filetext) -> String in
               return filetext
            } ?? "css error"

            blog.css = File(bloguuid: blog.uuid, filename: File.STYLESCSS, filetext: csstext)
            
            try self.db.updateFile(file:blog.css)
        }
        
        
        if blog.engine == nil
        {
            let enginetext = try self.getSampleFile(blog: blog, filename: File.BLOGENGINE)
            { (filetext) -> String in
              return filetext
            } ?? "blogengine error"

            blog.engine = File(bloguuid: blog.uuid, filename: File.BLOGENGINE, filetext: enginetext)
            
            try self.db.updateFile(file:blog.engine)
        }
    }
    
 
    func saveSupportFiles(blog:Blog) throws
    {
        do
        {
            try saveFile(file:blog.css)
            try saveFile(file:blog.html)
            try saveFile(file:blog.engine)
        }
        catch
        {
            throw ModelError(msg:"Error saving support files to database: \(error)")
        }
    }
    
    
    func getSampleFile(blog:Blog,filename:String,processBlock: @escaping (String) -> String) throws -> String?
    {
       guard let path = Bundle.main.path(forResource:filename, ofType:nil) else { return nil }

       var filetext : String

       do
       {
           filetext = try String(contentsOfFile: path)
       }
       catch
       {
           throw ModelError(msg:"Error getting sampelefile \(filename): \(error)")
       }

       filetext = processBlock(filetext)

       return filetext
    }
   
    
    
}
