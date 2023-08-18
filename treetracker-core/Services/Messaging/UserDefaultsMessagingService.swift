//
//  UserDefaultsMessagingService.swift
//  Treetracker-Core
//
//  Created by Frédéric Helfer on 17/08/23.
//

import Foundation

protocol UserDefaultsMessagingProtocol {
    func getLastSyncTime() -> Date?
    func updateLastSyncTime()
}

class UserDefaultsMessagingService: UserDefaultsMessagingProtocol {

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    private let key = "lastSyncTime"

    func getLastSyncTime() -> Date? {
        return userDefaults.value(forKey: key) as? Date
    }

    func updateLastSyncTime() {
        userDefaults.set(Date(), forKey: key)
    }
}
