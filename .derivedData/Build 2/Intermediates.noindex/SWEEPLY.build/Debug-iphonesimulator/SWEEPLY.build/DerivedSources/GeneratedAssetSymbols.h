#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"SWEEPLY.APP";

/// The "LaunchBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "AllSetImage" asset catalog image resource.
static NSString * const ACImageNameAllSetImage AC_SWIFT_PRIVATE = @"AllSetImage";

/// The "GetStartedBG" asset catalog image resource.
static NSString * const ACImageNameGetStartedBG AC_SWIFT_PRIVATE = @"GetStartedBG";

/// The "IntroOnboardingHero" asset catalog image resource.
static NSString * const ACImageNameIntroOnboardingHero AC_SWIFT_PRIVATE = @"IntroOnboardingHero";

/// The "LocationImage" asset catalog image resource.
static NSString * const ACImageNameLocationImage AC_SWIFT_PRIVATE = @"LocationImage";

/// The "LoginBackground" asset catalog image resource.
static NSString * const ACImageNameLoginBackground AC_SWIFT_PRIVATE = @"LoginBackground";

/// The "MascotSweeply" asset catalog image resource.
static NSString * const ACImageNameMascotSweeply AC_SWIFT_PRIVATE = @"MascotSweeply";

/// The "NotificationsImage" asset catalog image resource.
static NSString * const ACImageNameNotificationsImage AC_SWIFT_PRIVATE = @"NotificationsImage";

/// The "SignupImage" asset catalog image resource.
static NSString * const ACImageNameSignupImage AC_SWIFT_PRIVATE = @"SignupImage";

/// The "SplashLogo" asset catalog image resource.
static NSString * const ACImageNameSplashLogo AC_SWIFT_PRIVATE = @"SplashLogo";

/// The "SweeplyLogo" asset catalog image resource.
static NSString * const ACImageNameSweeplyLogo AC_SWIFT_PRIVATE = @"SweeplyLogo";

#undef AC_SWIFT_PRIVATE
