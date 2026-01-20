//
//  AppDelegate.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/19/26.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let sceneConfiguration = UISceneConfiguration(
      name: "Infineon Project - App Delegate", sessionRole: connectingSceneSession.role)
    sceneConfiguration.delegateClass = SceneDelegate.self
    return sceneConfiguration
  }
}
