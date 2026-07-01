//
//  CalarmWidgetExtensionBundle.swift
//  CalarmWidgetExtension
//
//

import SwiftUI
import WidgetKit

@main
struct CalarmWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        CalarmWidgetExtension()
        CalarmWidgetExtensionControl()
        CalarmWidgetExtensionLiveActivity()
    }
}
