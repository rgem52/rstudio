#
# SessionPackages.R
#
# Copyright (C) 2009-12 by RStudio, Inc.
#
# Unless you have received this program directly from RStudio pursuant
# to the terms of a commercial license agreement with RStudio, then
# this program is licensed to you under the terms of version 3 of the
# GNU Affero General Public License. This program is distributed WITHOUT
# ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
# MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
# AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
#
#

.rs.addFunction( "updatePackageEvents", function()
{
   reportPackageStatus <- function(status)
      function(pkgname, ...)
      {
         packageStatus = list(name=pkgname,
                              path=.rs.pathPackage(pkgname, quiet=TRUE),
                              loaded=status)
         .rs.enqueClientEvent("package_status_changed", packageStatus)
      }
   
   notifyPackageLoaded <- function(pkgname, ...)
   {
      .Call("rs_packageLoaded", pkgname)
   }

   notifyPackageUnloaded <- function(pkgname, ...)
   {
      .Call("rs_packageUnloaded", pkgname)
   }
   
   sapply(.packages(TRUE), function(packageName) 
   {
      if ( !(packageName %in% .rs.hookedPackages) )
      {
         attachEventName = packageEvent(packageName, "attach")
         setHook(attachEventName, reportPackageStatus(TRUE), action="append")
         
         loadEventName = packageEvent(packageName, "onLoad")
         setHook(loadEventName, notifyPackageLoaded, action="append")

         unloadEventName = packageEvent(packageName, "onUnload")
         setHook(unloadEventName, notifyPackageUnloaded, action="append")
             
         detachEventName = packageEvent(packageName, "detach")
         setHook(detachEventName, reportPackageStatus(FALSE), action="append")
          
         .rs.setVar("hookedPackages", append(.rs.hookedPackages, packageName))
      }
   })
})

.rs.addFunction( "packages.initialize", function()
{  
   # list of packages we have hooked attach/detach for
   .rs.setVar( "hookedPackages", character() )

   # set flag indicating we should not ignore loadedPackageUpdates checks
   .rs.setVar("ignoreNextLoadedPackageCheck", FALSE)
    
   # ensure we are subscribed to package attach/detach events
   .rs.updatePackageEvents()
   
   # whenever a package is installed notify the client and make sure
   # we are subscribed to its attach/detach events
   .rs.registerReplaceHook("install.packages", "utils", function(original,
                                                                pkgs,
                                                                lib,
                                                                repos = getOption("repos"),
                                                                ...) 
   {
      if (!.Call("rs_canInstallPackages"))
      {
        stop("Package installation is disabled in this version of RStudio",
             call. = FALSE)
      }
      
      if (!is.null(repos) && .rs.loadedPackageUpdates(pkgs)) {

         # attempt to determine the install command
         if (length(sys.calls()) > 7) {
            installCall <- sys.call(-7)
            installCmd <- format(installCall)
         } else {
            installCmd <- NULL
         }

         # call back into rsession to send an event to the client
         .rs.enqueLoadedPackageUpdates(installCmd)

         # throw error
         stop("Updating loaded packages")
      }

      # fixup path as necessary
      .rs.addRToolsToPath()

      # do housekeeping after we execute the original
      on.exit({
         .rs.updatePackageEvents()
         .rs.enqueClientEvent("installed_packages_changed")
         .rs.restorePreviousPath()
      })

      # call original
      original(pkgs, lib, repos, ...)
   })
   
   # whenever a package is removed notify the client (leave attach/detach
   # alone because the dangling event is harmless and removing it would
   # requrie somewhat involved code
   .rs.registerReplaceHook("remove.packages", "utils", function(original,
                                                               pkgs,
                                                               lib,
                                                               ...) 
   {
      # do housekeeping after we execute the original
      on.exit(.rs.enqueClientEvent("installed_packages_changed"))
                         
      # call original
      original(pkgs, lib, ...) 
   })
})

.rs.addFunction( "addRToolsToPath", function()
{
    .Call("rs_addRToolsToPath")
})

.rs.addFunction( "restorePreviousPath", function()
{
    .Call("rs_restorePreviousPath")
})

.rs.addFunction( "uniqueLibraryPaths", function()
{
   # get library paths (normalize on unix to get rid of duplicate symlinks)
   libPaths <- .libPaths()
   if (!identical(.Platform$OS.type, "windows"))
      libPaths <- .rs.normalizePath(libPaths)

   uniqueLibPaths <- subset(libPaths, !duplicated(libPaths))
   return (uniqueLibPaths)
})

.rs.addFunction( "writeableLibraryPaths", function()
{
   uniqueLibraryPaths <- .rs.uniqueLibraryPaths()
   writeableLibraryPaths <- character()
   for (libPath in uniqueLibraryPaths)
      if (.rs.isLibraryWriteable(libPath))
         writeableLibraryPaths <- append(writeableLibraryPaths, libPath)
   return (writeableLibraryPaths)
})

.rs.addFunction("defaultUserLibraryPath", function()
{
   unlist(strsplit(Sys.getenv("R_LIBS_USER"),
                              .Platform$path.sep))[1L]
})

.rs.addFunction("defaultLibraryPath", function()
{
  .libPaths()[1]
})

.rs.addJsonRpcHandler( "is_package_loaded", function(packageName, libName)
{
   .rs.scalar( (packageName %in% .packages()) &&
               identical(.rs.pathPackage(packageName, quiet=TRUE),
                         paste(libName, packageName, sep="/"))
             )
})

.rs.addFunction("forceUnloadPackage", function(name)
{
  if (name %in% .packages())
  {
    fullName <- paste("package:", name, sep="")
    suppressWarnings(detach(fullName, 
                            character.only=TRUE, 
                            unload=TRUE, 
                            force=TRUE))
    
    pkgDLL <- getLoadedDLLs()[[name]]
    if (!is.null(pkgDLL)) {
      suppressWarnings(library.dynam.unload(name, 
                                            system.file(package=name)))
    }
  }
})

.rs.addFunction("libPathsString", function()
{
   paste(.libPaths(), collapse = .Platform$path.sep)
})

.rs.addFunction("packageVersion", function(name, libPath, pkgs)
{
   pkgs <- subset(pkgs, Package == name & LibPath == libPath)
   if (nrow(pkgs) == 1)
      pkgs$Version
   else
      ""
})

.rs.addFunction( "initDefaultUserLibrary", function()
{
  userdir <- .rs.defaultUserLibraryPath()
  dir.create(userdir, showWarnings = FALSE, recursive = TRUE)
  .libPaths(c(userdir, .libPaths()))
})

.rs.addFunction("ensureWriteableUserLibrary", function()
{
   if (!.rs.defaultLibPathIsWriteable())
      .rs.initDefaultUserLibrary()
})

.rs.addFunction( "initializeRStudioPackages", function(libDir,
                                                       pkgSrcDir,
                                                       rsVersion,
                                                       force) {
  
  if (getRversion() >= "3.0.0") {
    
    # make sure the default library is writeable
    .rs.ensureWriteableUserLibrary()

    # function to update a package if necessary
    updateIfNecessary <- function(pkgName) {
      isInstalled <- .rs.isPackageInstalled(pkgName, .rs.defaultLibraryPath())
      if (force || !isInstalled || (.rs.getPackageVersion(pkgName) != rsVersion)) {
        
        # remove if necessary
        if (isInstalled)
          utils::remove.packages(pkgName, .rs.defaultLibraryPath())
        
        # call back into rstudio to install
        .Call("rs_installPackage", 
              file.path(pkgSrcDir, pkgName),
              .rs.defaultLibraryPath())
      }
    }
    
    updateIfNecessary("rstudio")
    updateIfNecessary("manipulate")
    
  } else {
    .rs.libPathsAppend(libDir)
  }
  
})

.rs.addJsonRpcHandler( "list_packages", function()
{
   # calculate unique libpaths
   uniqueLibPaths <- .rs.uniqueLibraryPaths()

   # get packages
   x <- suppressWarnings(library(lib.loc=uniqueLibPaths))
   x <- x$results[x$results[, 1] != "base", ]
   
   # extract/compute required fields 
   pkgs.name <- x[, 1]
   pkgs.library <- x[, 2]
   pkgs.desc <- x[, 3]
   pkgs.url <- file.path("help/library",
                         pkgs.name, 
                         "html", 
                         "00Index.html")
   loaded.pkgs <- .rs.pathPackage()
   pkgs.loaded <- !is.na(match(paste(pkgs.library,pkgs.name, sep="/"),
                               loaded.pkgs))
   

   # build up vector of package versions
   instPkgs <- as.data.frame(installed.packages(), stringsAsFactors=F)
   pkgs.version <- character(length=length(pkgs.name))
   for (i in 1:length(pkgs.name)) {
      pkgs.version[[i]] <- .rs.packageVersion(pkgs.name[[i]],
                                              pkgs.library[[i]],
                                              instPkgs)
   }

   # return data frame sorted by name
   packages = data.frame(name=pkgs.name,
                         library=pkgs.library,
                         version=pkgs.version,
                         desc=pkgs.desc,
                         url=pkgs.url,
                         loaded=pkgs.loaded,
                         check.rows = TRUE,
                         stringsAsFactors = FALSE)

   # sort and return
   packages[order(packages$name),]
})

.rs.addJsonRpcHandler( "get_package_install_context", function()
{
   # cran mirror configured
   repos = getOption("repos")
   cranMirrorConfigured <- !is.null(repos) && repos != "@CRAN@"
   
   # selected repository names
   selectedRepositoryNames <- names(repos)

   # package archive extension
   if (identical(.Platform$OS.type, "windows"))
      packageArchiveExtension <- ".zip; .tar.gz"
   else if (identical(substr(.Platform$pkgType, 1L, 10L), "mac.binary"))
      packageArchiveExtension <- ".tgz; .tar.gz"
   else
      packageArchiveExtension <- ".tar.gz"

   # default library path (normalize on unix)
   defaultLibraryPath = .libPaths()[1L]
   if (!identical(.Platform$OS.type, "windows"))
      defaultLibraryPath <- .rs.normalizePath(defaultLibraryPath)
   
   # return context
   list(cranMirrorConfigured = cranMirrorConfigured,
        selectedRepositoryNames = selectedRepositoryNames,
        packageArchiveExtension = packageArchiveExtension,
        defaultLibraryPath = defaultLibraryPath,
        defaultLibraryWriteable = .rs.defaultLibPathIsWriteable(),
        writeableLibraryPaths = .rs.writeableLibraryPaths(),
        defaultUserLibraryPath = .rs.defaultUserLibraryPath(),
        devModeOn = .rs.devModeOn())
})

.rs.addJsonRpcHandler( "get_cran_mirrors", function()
{
   # RStudio mirror
   rstudioDF <- data.frame(name = "Global (CDN)",
                           host = "RStudio",
                           url = "http://cran.rstudio.com",
                           country = "us",
                           stringsAsFactors = FALSE)

   # CRAN mirrors
   cranMirrors <- utils::getCRANmirrors()
   cranDF <- data.frame(name = cranMirrors$Name,
                        host = cranMirrors$Host,
                        url = cranMirrors$URL,
                        country = cranMirrors$CountryCode,
                        stringsAsFactors = FALSE)

   # return mirrors
   rbind(rstudioDF, cranDF)
})

.rs.addJsonRpcHandler( "init_default_user_library", function()
{
  .rs.initDefaultUserLibrary()
})


.rs.addJsonRpcHandler( "check_for_package_updates", function()
{
   # get updates writeable libraries and convert to a data frame
   updates <- as.data.frame(utils::old.packages(lib.loc =
                                          .rs.writeableLibraryPaths()),
                            stringsAsFactors = FALSE)
   row.names(updates) <- NULL
   
   # see which ones are from CRAN and add a news column for them
   cranRep <- getOption("repos")["CRAN"]
   cranRepLen <- nchar(cranRep)
   isFromCRAN <- cranRep == substr(updates$Repository, 1, cranRepLen)
   newsURL <- character(nrow(updates))
   if (substr(cranRep, cranRepLen, cranRepLen) != "/")
      cranRep <- paste(cranRep, "/", sep="")

   newsURL[isFromCRAN] <- paste(cranRep,
                                "web/packages/",
                                updates$Package,
                                "/NEWS", sep = "")[isFromCRAN]
   
   updates <- data.frame(packageName = updates$Package,
                         libPath = updates$LibPath,
                         installed = updates$Installed,
                         available = updates$ReposVer,
                         newsUrl = newsURL,
                         stringsAsFactors = FALSE)
                       
                       
   return (updates)
})

.rs.addFunction("packagesLoaded", function(pkgs) {
   # first check loaded namespaces
   if (any(pkgs %in% loadedNamespaces()))
      return(TRUE)

   # now check if there are libraries still loaded in spite of the
   # namespace being unloaded 
   libs <- .dynLibs()
   libnames <- vapply(libs, "[[", character(1), "name")
   return(any(pkgs %in% libnames))
})

.rs.addFunction("loadedPackageUpdates", function(pkgs)
{
   # are we ignoring?
   ignore <- .rs.ignoreNextLoadedPackageCheck
   .rs.setVar("ignoreNextLoadedPackageCheck", FALSE)
   if (ignore)
      return(FALSE)

   # if the default set of namespaces in rstudio are loaded
   # then skip the check
   defaultNamespaces <- c("base", "datasets", "graphics", "grDevices",
                          "methods", "stats", "tools", "utils")
   if (identical(defaultNamespaces, loadedNamespaces()) &&
       length(.dynLibs()) == 4)
      return(FALSE)

   if (.rs.packagesLoaded(pkgs)) {
      return(TRUE)
   }
   else {
      avail <- available.packages()
      deps <- suppressMessages(suppressWarnings(
         utils:::getDependencies(pkgs, available=avail)))
      return(.rs.packagesLoaded(deps))
   }
})

.rs.addFunction("enqueLoadedPackageUpdates", function(installCmd)
{
   .Call("rs_enqueLoadedPackageUpdates", installCmd)
})

.rs.addJsonRpcHandler("loaded_package_updates_required", function(pkgs)
{
   .rs.scalar(.rs.loadedPackageUpdates(as.character(pkgs)))
})

.rs.addJsonRpcHandler("ignore_next_loaded_package_check", function() {
   .rs.setVar("ignoreNextLoadedPackageCheck", TRUE)
   return(NULL)
})

