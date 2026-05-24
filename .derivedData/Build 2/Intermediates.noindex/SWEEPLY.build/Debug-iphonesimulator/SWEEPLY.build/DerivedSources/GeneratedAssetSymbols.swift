import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "LaunchBackground" asset catalog color resource.
    static let launchBackground = DeveloperToolsSupport.ColorResource(name: "LaunchBackground", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "AllSetImage" asset catalog image resource.
    static let allSet = DeveloperToolsSupport.ImageResource(name: "AllSetImage", bundle: resourceBundle)

    /// The "GetStartedBG" asset catalog image resource.
    static let getStartedBG = DeveloperToolsSupport.ImageResource(name: "GetStartedBG", bundle: resourceBundle)

    /// The "IntroOnboardingHero" asset catalog image resource.
    static let introOnboardingHero = DeveloperToolsSupport.ImageResource(name: "IntroOnboardingHero", bundle: resourceBundle)

    /// The "LocationImage" asset catalog image resource.
    static let location = DeveloperToolsSupport.ImageResource(name: "LocationImage", bundle: resourceBundle)

    /// The "LoginBackground" asset catalog image resource.
    static let loginBackground = DeveloperToolsSupport.ImageResource(name: "LoginBackground", bundle: resourceBundle)

    /// The "MascotSweeply" asset catalog image resource.
    static let mascotSweeply = DeveloperToolsSupport.ImageResource(name: "MascotSweeply", bundle: resourceBundle)

    /// The "NotificationsImage" asset catalog image resource.
    static let notifications = DeveloperToolsSupport.ImageResource(name: "NotificationsImage", bundle: resourceBundle)

    /// The "SignupImage" asset catalog image resource.
    static let signup = DeveloperToolsSupport.ImageResource(name: "SignupImage", bundle: resourceBundle)

    /// The "SplashLogo" asset catalog image resource.
    static let splashLogo = DeveloperToolsSupport.ImageResource(name: "SplashLogo", bundle: resourceBundle)

    /// The "SweeplyLogo" asset catalog image resource.
    static let sweeplyLogo = DeveloperToolsSupport.ImageResource(name: "SweeplyLogo", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "AllSetImage" asset catalog image.
    static var allSet: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .allSet)
#else
        .init()
#endif
    }

    /// The "GetStartedBG" asset catalog image.
    static var getStartedBG: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .getStartedBG)
#else
        .init()
#endif
    }

    /// The "IntroOnboardingHero" asset catalog image.
    static var introOnboardingHero: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .introOnboardingHero)
#else
        .init()
#endif
    }

    /// The "LocationImage" asset catalog image.
    static var location: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .location)
#else
        .init()
#endif
    }

    /// The "LoginBackground" asset catalog image.
    static var loginBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .loginBackground)
#else
        .init()
#endif
    }

    /// The "MascotSweeply" asset catalog image.
    static var mascotSweeply: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .mascotSweeply)
#else
        .init()
#endif
    }

    /// The "NotificationsImage" asset catalog image.
    static var notifications: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .notifications)
#else
        .init()
#endif
    }

    /// The "SignupImage" asset catalog image.
    static var signup: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .signup)
#else
        .init()
#endif
    }

    /// The "SplashLogo" asset catalog image.
    static var splashLogo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .splashLogo)
#else
        .init()
#endif
    }

    /// The "SweeplyLogo" asset catalog image.
    static var sweeplyLogo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .sweeplyLogo)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "AllSetImage" asset catalog image.
    static var allSet: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .allSet)
#else
        .init()
#endif
    }

    /// The "GetStartedBG" asset catalog image.
    static var getStartedBG: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .getStartedBG)
#else
        .init()
#endif
    }

    /// The "IntroOnboardingHero" asset catalog image.
    static var introOnboardingHero: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .introOnboardingHero)
#else
        .init()
#endif
    }

    /// The "LocationImage" asset catalog image.
    static var location: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .location)
#else
        .init()
#endif
    }

    /// The "LoginBackground" asset catalog image.
    static var loginBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .loginBackground)
#else
        .init()
#endif
    }

    /// The "MascotSweeply" asset catalog image.
    static var mascotSweeply: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .mascotSweeply)
#else
        .init()
#endif
    }

    /// The "NotificationsImage" asset catalog image.
    static var notifications: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .notifications)
#else
        .init()
#endif
    }

    /// The "SignupImage" asset catalog image.
    static var signup: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .signup)
#else
        .init()
#endif
    }

    /// The "SplashLogo" asset catalog image.
    static var splashLogo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .splashLogo)
#else
        .init()
#endif
    }

    /// The "SweeplyLogo" asset catalog image.
    static var sweeplyLogo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .sweeplyLogo)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

