//
//  RLTransaction.m
//  RunloopTransaction
//
//  Created by 张尉 on 2018/7/23.
//  Copyright © 2018年 Wayne. All rights reserved.
//

#import "RLTransaction.h"
#import "CoreGraphics/CGGeometry.h"

#define RL_BOXABLE __attribute__((objc_boxable))

struct RLTransactionDescription {
    CFRunLoopRef runloop;
    CFRunLoopActivity activity;
    CFIndex order;
    CFRunLoopMode mode;
};
typedef struct RLTransactionDescription RLTransactionDescription;
typedef RLTransactionDescription* RLTransactionDescriptionRef;


static
NSMutableArray* __RLTransactionGetSet()
{
    static NSMutableArray *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSMutableArray arrayWithCapacity:10];
    });
    return set;
}

static
dispatch_queue_t __RLTransactionGetQueue()
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INITIATED,
                                                                             0);
        queue = dispatch_queue_create("__RLTransactionQueue", attr);
    });
    return queue;
}
#define __RLTLock(block) dispatch_sync(__RLTransactionGetQueue(), block);

static
void __RLTransactionAddAction(void (^action)(void))
{
    __RLTLock(^{
        NSMutableArray *set = __RLTransactionGetSet();
        [set addObject:action];
    });
}

static
void __RLTransactionClean()
{
    __RLTLock(^{
        NSMutableArray *set = __RLTransactionGetSet();
        [set removeAllObjects];
    });
}

static
void __RLTransactionSetup()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RLTransactionDescription rltDesc = {
            .runloop  = CFRunLoopGetMain(),
            .activity = kCFRunLoopBeforeWaiting | kCFRunLoopExit,
            .order    = LONG_MAX,
            .mode     = kCFRunLoopCommonModes,
        };
        
        CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, rltDesc.activity, true, rltDesc.order, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            
            NSArray *set = __RLTransactionGetSet().copy;
            if (set.count == 0)
                return;
            
            __RLTransactionClean();
            [set enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                void (^action)(void) = obj;
                action();
            }];
        });
        
        CFRunLoopAddObserver(rltDesc.runloop, observer, rltDesc.mode);
        CFRelease(observer);
    });
}

extern
void RLTransactionCommit(void (^action)(void))
{
    __RLTransactionSetup();
    __RLTransactionAddAction(action);
}
