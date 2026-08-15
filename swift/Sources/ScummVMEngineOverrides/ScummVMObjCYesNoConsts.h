#ifndef SCUMMVM_OBJC_YES_NO_CONSTS_H
#define SCUMMVM_OBJC_YES_NO_CONSTS_H

#ifdef __OBJC__
#import <Foundation/Foundation.h>

#ifdef YES
#undef YES
#endif
#ifdef NO
#undef NO
#endif

static const BOOL YES = (BOOL)1;
static const BOOL NO = (BOOL)0;
#endif

#endif
