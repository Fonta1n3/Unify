//
//  Pay_JoinApp.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import SwiftUI

@main
struct UnifyApp: App {
    @StateObject private var manager: DataManager = DataManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(manager)
                .environment(\.managedObjectContext, manager.container.viewContext)
        }
    }
}
