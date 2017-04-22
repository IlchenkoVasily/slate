/*
    Copyright 2016, Mitch Curtis

    This file is part of Slate.

    Slate is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Slate is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Slate. If not, see <http://www.gnu.org/licenses/>.
*/

import QtQuick 2.8
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
import QtQuick.Controls 2.1

import Qt.labs.platform 1.0 as Platform

import App 1.0

import "ui" as Ui

/*
    TODO:
    - fix disappearing hue slider indicator
    - native menubars?
    - fix performance when drawing pixels
    - fix performance when resizing
    - make panels resizable
    - tutorial?
    - add "lighten/darken current colour" feature with convenient keyboard shortcuts.
      it could display a fading indicator like the zoom level does, comparing the
      proposed colour next to the old one. could be a mouse wheel shortcut.
    - add support for selection marquees (within individual tile bounds)
*/

ApplicationWindow {
    id: window
    objectName: "window"
    width: 1200
    height: 800
//    width: 1080
//    height: 1920
    title: qtbug53394Title
    visible: true

    property string qtbug53394Title: project && project.loaded ? ((project.url.length > 0 ? project.url.toString() : "Untitled") + (project.unsavedChanges ? "*" : "")) : ""

    readonly property int controlSpacing: 10

    property var project: projectManager.project
    property var canvas: canvasContainer.canvas
    property alias newProjectPopup: newProjectPopup
    property alias openProjectDialog: openProjectDialog
    property alias saveChangesDialog: discardChangesDialog

    onClosing: {
        close.accepted = false;
        doIfChangesDiscarded(function() { Qt.quit() })
    }

    // If we set the image URL immediately, it can happen before
    // the error popup is ready.
    Component.onCompleted: {
        contentItem.objectName = "applicationWindowContentItem";

        if (settings.loadLastOnStartup && settings.lastProjectUrl.toString().length > 0) {
            project.load(settings.lastProjectUrl);
        } else {
            createNewProject("image")
        }

        window.title = Qt.binding(function(){ return qtbug53394Title });
        window.x = Screen.desktopAvailableWidth / 2 - width / 2
        window.y = Screen.desktopAvailableHeight / 2 - height / 2
    }

    function doIfChangesDiscarded(actionFunction, discardChangesBeforeAction) {
        if (!project) {
            // Auto tests can skip this function.
            return;
        }

        if (!project.unsavedChanges) {
            if (!!discardChangesBeforeAction)
                project.close();
            actionFunction();
            return;
        }

        function disconnectSignals() {
            saveChangesDialog.accepted.disconnect(discardChanges);
            saveChangesDialog.rejected.disconnect(dontDiscardChanges);
        }

        function discardChanges() {
            if (!!discardChangesBeforeAction)
                project.close()
            actionFunction();
            disconnectSignals();
        }

        function dontDiscardChanges() {
            disconnectSignals();
        }

        saveChangesDialog.accepted.connect(discardChanges);
        saveChangesDialog.rejected.connect(dontDiscardChanges);
        saveChangesDialog.open();
    }

    Connections {
        target: projectManager.project ? projectManager.project : null
        onErrorOccurred: errorPopup.showError(errorMessage)
    }

    ProjectManager {
        id: projectManager
        applicationSettings: settings

        function saveOrSaveAs() {
            if (project.url.toString().length > 0) {
                project.save();
            } else {
                saveAsDialog.open();
            }
        }
    }

    FontMetrics {
        id: fontMetrics
    }

    Ui.Shortcuts {
        window: window
        project: window.project
        canvas: window.canvas
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Ui.CanvasContainer {
            id: canvasContainer
            focus: true

            project: projectManager.project
            projectType: projectManager.type
            checkedToolButton: iconToolBar.toolButtonGroup.checkedButton

            Layout.preferredWidth: window.width / 3
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        ColumnLayout {
            Ui.ColourPanel {
                id: colourPanel
                canvas: window.canvas
            }

            SimpleLoader {
                // TODO: this loader receives the typeChanged signal before CanvasContainer
                // has had a chance to load the new canvas, so there's an error on
                // "tileCanvas: window.canvas". Find a better way of ensuring this
                // loader is only active when a TileCanvas is loaded.
                objectName: "tilesetSwatchLoader"
                active: projectManager.type === "tileset" && window.canvas && window.canvas.hasOwnProperty("penTile")
                sourceComponent: Ui.TilesetSwatch {
                    id: tilesetSwatch
                    objectName: "tilesetSwatch"
                    tileCanvas: window.canvas
                    project: window.project
                    // Don't let e.g. the pencil icon go under us.
                    z: canvasContainer.z - 1
                }

                Layout.preferredWidth: colourPanel.implicitWidth
                Layout.preferredHeight: window.contentItem.height / 2
                Layout.fillHeight: true
            }
        }
    }

    header: Ui.ToolBar {
        objectName: "toolBar"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Ui.MenuBar {
                id: menuBar
                spacing: controlSpacing
                project: window.project
                canvas: window.canvas
            }

            Ui.IconToolBar {
                id: iconToolBar
                project: window.project
                canvas: window.canvas
                fontMetrics: fontMetrics

                Layout.fillWidth: true
            }
        }
    }

    Platform.FileDialog {
        id: openProjectDialog
        nameFilters: ["JSON files (*.json)"]
        defaultSuffix: "json"
        onAccepted: project.load(file)
    }

    Platform.FileDialog {
        id: saveAsDialog
        fileMode: Platform.FileDialog.SaveFile
        nameFilters: ["JSON files (*.json)"]
        defaultSuffix: "json"
        onAccepted: project.saveAs(file)
    }

    Ui.ErrorPopup {
        id: errorPopup
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        // TODO: shouldn't have to do this, but not even a FocusScope around TileCanvas worked..
        onVisibleChanged: canvas.focus = true
    }

    Ui.NewProjectPopup {
        id: newProjectPopup
        x: parent.width / 2 - width / 2
        // Avoid binding loop that results from using height.
        // TODO: https://codereview.qt-project.org/#/c/175024/ fixes this
        y: parent.height / 2 - implicitHeight / 2

        onChoseTilesetProject: newTilesetProjectPopup.open()
        onChoseImageProject: newImageProjectPopup.open()
        onRejected: canvas.focus = true
    }

    function createNewProject(type) {
        projectManager.beginCreation(type);

        if (type === "tileset") {
            var p = newTilesetProjectPopup;
            projectManager.temporaryProject.createNew(p.tilesetPath, p.tileWidth, p.tileHeight,
                p.tilesetTilesWide, p.tilesetTilesHigh, p.canvasTilesWide, p.canvasTilesHigh,
                p.transparentBackground);
        } else {
            var p = newImageProjectPopup;
            projectManager.temporaryProject.createNew(p.imageWidth, p.imageHeight, p.transparentBackground);
        }

        projectManager.completeCreation();
    }

    Ui.NewTilesetProjectPopup {
        id: newTilesetProjectPopup
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        onVisibleChanged: canvas.focus = true

        onAccepted: createNewProject("tileset")
    }

    Ui.NewImageProjectPopup {
        id: newImageProjectPopup
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        onVisibleChanged: window.canvas.focus = true

        onAccepted: createNewProject("image")
    }

    Ui.RecentProjectsPopup {
        id: recentProjectsPopup
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        onVisibleChanged: canvas.focus = true

        onAccepted: project.load(fileName)
    }

    Ui.OptionsDialog {
        id: optionsDialog
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - implicitHeight / 2
        onVisibleChanged: canvas.focus = true
    }

    Dialog {
        id: discardChangesDialog
        objectName: "discardChangesDialog"
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        title: qsTr("Unsaved changes")
        standardButtons: Dialog.Yes | Dialog.No

        Label {
            text: qsTr("The action you're about to perform could discard changes.\n\nContinue anyway?")
        }
    }
}
