/*
 * selene: display refresh rate page for Lomiri System Settings.
 *
 * The choice is stored in GSettings (com.selene.display refresh-rate);
 * selene-refresh-rate-watch.service notices the change and applies it as root
 * through /usr/bin/selene-refresh-rate.
 */
import QtQuick 2.12
import SystemSettings 1.0
import Lomiri.Components 1.3
import Lomiri.Components.ListItems 1.3 as ListItem
import GSettings 1.0

ItemPage {
    id: root
    objectName: "displayRefreshPage"
    title: i18n.tr("Refresh rate")

    GSettings {
        id: displaySettings
        schema.id: "com.selene.display"
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.childrenRect.height

        Column {
            id: column
            anchors { left: parent.left; right: parent.right }

            ListItem.ItemSelector {
                id: rateSelector
                text: i18n.tr("Screen refresh rate")
                expanded: true
                model: [i18n.tr("90 Hz (smooth)"), i18n.tr("60 Hz (saves battery)")]
                selectedIndex: displaySettings.refreshRate === 60 ? 1 : 0
                onDelegateClicked: displaySettings.refreshRate = (index === 1 ? 60 : 90)
            }

            ListItem.Caption {
                text: i18n.tr("90 Hz makes scrolling and animations smoother but uses more battery while the screen is on. The change applies within a second.")
            }
        }
    }
}
