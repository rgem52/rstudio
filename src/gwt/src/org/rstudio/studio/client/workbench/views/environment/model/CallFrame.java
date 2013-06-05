/*
 * CallFrame.java
 *
 * Copyright (C) 2009-12 by RStudio, Inc.
 *
 * Unless you have received this program directly from RStudio pursuant
 * to the terms of a commercial license agreement with RStudio, then
 * this program is licensed to you under the terms of version 3 of the
 * GNU Affero General Public License. This program is distributed WITHOUT
 * ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
 * AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
 *
 */

package org.rstudio.studio.client.workbench.views.environment.model;

import com.google.gwt.core.client.JavaScriptObject;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.view.client.ProvidesKey;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.common.filetypes.events.OpenSourceFileEvent;

public class CallFrame extends JavaScriptObject
{
   protected CallFrame()
   {
   }

   public final native String getFunctionName() /*-{
       return this.function_name;
   }-*/;

   public final native int getContextDepth() /*-{
       return this.context_depth;
   }-*/;

   public final native String getFileName() /*-{
       return this.file_name;
   }-*/;

   public final native int getLineNumber() /*-{
       return this.line_number;
   }-*/;
}

