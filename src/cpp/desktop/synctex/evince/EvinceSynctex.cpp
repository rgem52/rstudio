/*
 * EvinceSynctex.cpp
 *
 * Copyright (C) 2009-12 by RStudio, Inc.
 *
 * This program is licensed to you under the terms of version 3 of the
 * GNU Affero General Public License. This program is distributed WITHOUT
 * ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
 * AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
 *
 */

#include "EvinceSynctex.hpp"

#include <boost/format.hpp>

#include <core/Log.hpp>
#include <core/Error.hpp>
#include <core/DateTime.hpp>

#include <DesktopMainWindow.hpp>
#include <DesktopUtils.hpp>

#include "EvinceDaemon.hpp"
#include "EvinceWindow.hpp"

// TODO: window activation

// TODO: no inverse search if the document was loaded using
//       evince -i <page> style invocation (because no connection)
//       (may need to poll for a connection with start == false)

// TODO: don't get the close event if we start with page style
//       (polling as described above would fix this)

// TODO: cold start from synctex when window closed doesn't always work
//       (wait for document loaded?)

// TODO: can't rely on global pdfPath_ in synctex (multiple viewers)

// TODO: handle differnet evince versions



// TODO: remove hard-coding for check-in



using namespace core;

namespace desktop {
namespace synctex {

namespace {

void logDBusError(const QDBusError& error, const ErrorLocation& location)
{
   boost::format fmt("Error %1% (%2%): %3%");
   std::string msg = boost::str(fmt % error.type() %
                                      error.name().toStdString() %
                                      error.message().toStdString());
   core::log::logErrorMessage(msg, location);
}

} // anonymous namespace

EvinceSynctex::EvinceSynctex(MainWindow* pMainWindow)
   : Synctex(pMainWindow)
{
   pEvince_ = new EvinceDaemon(this);
}

void EvinceSynctex::syncView(const QString& pdfFile,
                             const QString& srcFile,
                             const QPoint& srcLoc)
{
   if (windows_.contains(pdfFile))
   {
      syncView(windows_.value(pdfFile), srcFile, srcLoc);
   }
   else
   {
      // find the window
      QDBusPendingReply<QString> reply = pEvince_->FindDocument(
                                       QUrl::fromLocalFile(pdfFile).toString(),
                                       true);

      // wait for the results asynchronously
      QDBusPendingCallWatcher* pWatcher = new QDBusPendingCallWatcher(reply,
                                                                      this);
      SyncRequest request;
      request.pdfFile = pdfFile;
      request.srcFile = srcFile;
      request.srcLoc = srcLoc;
      pendingSyncRequests_.insert(pWatcher, request);

      QObject::connect(pWatcher,
                       SIGNAL(finished(QDBusPendingCallWatcher*)),
                       this,
                       SLOT(onFindWindowFinished(QDBusPendingCallWatcher*)));
   }
}

void EvinceSynctex::syncView(const QString& pdfFile, int page)
{
   QStringList args;
   args.append(QString::fromAscii("-i"));
   args.append(QString::fromStdString(boost::lexical_cast<std::string>(page)));
   args.append(pdfFile);
   QProcess::startDetached(QString::fromAscii("evince"), args);
}

void EvinceSynctex::onFindWindowFinished(QDBusPendingCallWatcher* pWatcher)
{
   // get the reply and the sync request params
   QDBusPendingReply<QString> reply = *pWatcher;
   SyncRequest req = pendingSyncRequests_.value(pWatcher);
   pendingSyncRequests_.remove(pWatcher);

   if (reply.isError())
   {
      logDBusError(reply.error(), ERROR_LOCATION);
   }
   else
   {
      // initialize a connection to it
      EvinceWindow* pWindow = new EvinceWindow(reply.value());
      if (!pWindow->isValid())
      {
         logDBusError(pWindow->lastError(), ERROR_LOCATION);
         return;
      }

      // put it in our map
      windows_.insert(req.pdfFile, pWindow);

      // sign up for events
      QObject::connect(pWindow,
                       SIGNAL(Closed()),
                       this,
                       SLOT(onClosed()));
      QObject::connect(pWindow,
                       SIGNAL(SyncSource(const QString&,const QPoint&,uint)),
                       this,
                       SLOT(onSyncSource(const QString&,const QPoint&,uint)));

      // perform sync
      syncView(pWindow, req.srcFile, req.srcLoc);
   }

   // delete the watcher
   pWatcher->deleteLater();
}

void EvinceSynctex::syncView(EvinceWindow* pWindow,
                             const QString& srcFile,
                             const QPoint& srcLoc)
{
   QDBusPendingReply<> reply = pWindow->SyncView(
                                       srcFile,
                                       srcLoc,
                                       core::date_time::secondsSinceEpoch());

   // wait for the results asynchronously
   QDBusPendingCallWatcher* pWatcher = new QDBusPendingCallWatcher(reply,
                                                                   this);
   QObject::connect(pWatcher,
                    SIGNAL(finished(QDBusPendingCallWatcher*)),
                    this,
                    SLOT(onSyncViewFinished(QDBusPendingCallWatcher*)));
}

void EvinceSynctex::onSyncViewFinished(QDBusPendingCallWatcher* pWatcher)
{
   QDBusPendingReply<QString> reply = *pWatcher;
   if (reply.isError())
      logDBusError(reply.error(), ERROR_LOCATION);

   pWatcher->deleteLater();
}

void EvinceSynctex::onClosed()
{
   // get the window that closed and determine the associated pdf
   EvinceWindow* pWindow = static_cast<EvinceWindow*>(sender());
   QString pdfFile = windows_.key(pWindow);

   // notify base
   Synctex::onClosed(pdfFile);

   // remove window
   windows_.remove(pdfFile);
   pWindow->deleteLater();
}


void EvinceSynctex::onSyncSource(const QString& srcFile,
                                 const QPoint& srcLoc,
                                 uint)
{
   QUrl fileUrl(srcFile);
   Synctex::onSyncSource(fileUrl.toLocalFile(), srcLoc);
}


} // namesapce synctex
} // namespace desktop