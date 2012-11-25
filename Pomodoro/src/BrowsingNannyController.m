#import "BrowsingNannyController.h"
#import "PomoNotifications.h"
#import "PomodoroController.h"
#import "Scripter.h"

static NSString * const DefaultsKeyEnabled = @"browsingNannyEnabled";
static NSString * const DefaultsKeyUrls = @"browsingNannyUrls";
static NSString * const GetUrlsScriptName = @"getActiveUrlsFromBrowsers";


/**
 More explanation on this pattern:  [Extra spaces added since slash star is a comment delimiter.]

 "http*://" matches "http://" as well as "https://" 
 "?" matches a single character, NOT 0 or 1 characters - so it cannot be used here.
 " / * " at the end is necessary to match all pages on this domain.
 Using "/ foo / *" instead of " / * " will only match paths that start with "/foo" - both "/foom" and "foo/bar"
 Using "/ foo / *" instead of " / * " will only match paths that start with "/foo/", but won't match "/foo" with no trailing slash.

 "*.blocked.com" will match "http://www.blocked.com" and "www.blocked.com" and "blocked.com" but also "mail.blocked.com" and "ftp://blocked.com"
 "*.blocked.com / *" is probably a more efficient pattern than "http * :// * .facebook.com / *", even if it is overly general. Up to you.

 NOTE: You could easily upgrade to regular expressions but I opted for simplicity here.
 See <https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/Predicates/Articles/pUsing.html#//apple_ref/doc/uid/TP40001794-SW9>
*/
static NSString * const DefaultUrlPattern = @"http*://*.blocked.com/*";

@interface BrowsingNannyController()
- (IBAction)removeUrlClicked:(id)sender;
- (IBAction)addUrlClicked:(id)sender;
- (NSDictionary *)urlPatternObjectWithPattern:(NSString *)pattern;
@end

#pragma mark -

@implementation BrowsingNannyController
@synthesize arrayController, scripter, pomodoroController, blacklistedPredicate;

- (void)awakeFromNib {
    self.blacklistedPredicate = [NSPredicate predicateWithValue:NO];
    [self registerForPomodoro:_PMPomoOncePerSecond method:@selector(oncePerSecond:)];
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:DefaultsKeyUrls
                                               options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
                                               context:nil];
}

- (void)dealloc {
    self.blacklistedPredicate = nil;
    self.pomodoroController = nil;
    self.arrayController = nil;
    self.scripter = nil;
    [super dealloc];
}

- (BOOL)enabled {
    return [self checkDefault:DefaultsKeyEnabled];
}

#pragma mark - Pomodoro notifications

- (void)oncePerSecond:(NSNotification*)notification {
    if (!self.enabled) return;
    //NSLog(@"Tick.");
    NSAppleEventDescriptor *result = [scripter executeScript:GetUrlsScriptName];
    for (NSInteger i = 1; i <= [result numberOfItems]; i++) {
        NSString *urlString = [[result descriptorAtIndex:i] stringValue];
        //NSLog(@"You're browsing %@", urlString);
        if ([blacklistedPredicate evaluateWithObject:urlString]) {
            //NSLog(@"The url %@ is blacklisted. Marking it an interruption!", urlString);
            [pomodoroController internalInterrupt:self];
            //One interruption is enough, don't need to keep going
            return;
        }
    }    
}

#pragma mark - Compile multiple rules into master predicate

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:DefaultsKeyUrls]) {
        NSArray *patternsArray = [change objectForKey:NSKeyValueChangeNewKey];
        //NSLog(@"change to urls: %@", patternsArray);
        NSPredicate *predicate = nil;
        if (![patternsArray isEqualTo:[NSNull null]] && [patternsArray count] > 0) {
            NSMutableArray *conditions = [NSMutableArray arrayWithCapacity:[patternsArray count]];
            for (NSDictionary *patternObj in patternsArray) {
                NSString *condition = [NSString stringWithFormat:@"(SELF LIKE \"%@\")",
                                       [[patternObj objectForKey:@"url"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
                [conditions addObject:condition];
            }
            NSString *completePredicateString = [conditions componentsJoinedByString:@" OR "];
            @try {
                predicate = [NSPredicate predicateWithFormat:completePredicateString];
            }
            @catch (NSException *exception) {
                NSLog(@"Invalid predicate format! %@", completePredicateString);
            }
        }
        //NSLog(@"Predicate: %@", predicate);
        self.blacklistedPredicate = (predicate)? predicate : [NSPredicate predicateWithValue:NO];
    }
}


#pragma mark - Preference Pane Management

- (IBAction)removeUrlClicked:(id)sender {
    if ([arrayController.selectionIndexes count] > 0) {
        [arrayController removeObjectsAtArrangedObjectIndexes:arrayController.selectionIndexes];
    }
}

- (IBAction)addUrlClicked:(id)sender {
    [arrayController addObject:[self urlPatternObjectWithPattern:nil]];
}

- (NSDictionary *)urlPatternObjectWithPattern:(NSString *)pattern {
    if (!pattern) pattern = DefaultUrlPattern;
    return [NSDictionary dictionaryWithObject:pattern forKey:@"url"];
}

@end
