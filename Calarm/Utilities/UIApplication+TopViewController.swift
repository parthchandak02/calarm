//
//  UIApplication+TopViewController.swift
//  Calarm
//

import UIKit

extension UIApplication {
    var calarmTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .calarmTopMostViewController
    }
}

private extension UIViewController {
    var calarmTopMostViewController: UIViewController {
        if let presented = presentedViewController {
            return presented.calarmTopMostViewController
        }
        if let navigation = self as? UINavigationController,
           let visible = navigation.visibleViewController {
            return visible.calarmTopMostViewController
        }
        if let tab = self as? UITabBarController,
           let selected = tab.selectedViewController {
            return selected.calarmTopMostViewController
        }
        return self
    }
}
