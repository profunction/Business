#import "GeneratedPluginRegistrant.h"

// AppDelegate.swift 要用 FLTFirebaseMessagingPlugin。<firebase_messaging/...> 是 CocoaPods 的路径；
// 这个 App 用 Swift Package Manager（没有 Podfile），要用 module（跟 firebase_messaging 的 example 一样）
#if __has_include(<firebase_messaging/FLTFirebaseMessagingPlugin.h>)
#import <firebase_messaging/FLTFirebaseMessagingPlugin.h>
#else
@import firebase_messaging;
#endif
