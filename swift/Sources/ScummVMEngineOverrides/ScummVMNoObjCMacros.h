#ifndef SCUMMVM_NO_OBJC_MACROS_H
#define SCUMMVM_NO_OBJC_MACROS_H

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#ifdef YES
#undef YES
#endif
#ifdef NO
#undef NO
#endif

#endif
