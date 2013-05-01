//
//  WDLViewController.m
//  Nature of Code
//
//  Created by William Lindmeier on 1/30/13.
//  Copyright (c) 2013 wdlindmeier. All rights reserved.
//

#import "NOCSketchViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>

@interface NOCSketchViewController ()
{
    BOOL _isDraggingDrawer;
    CGPoint _posDrawerClosed;
    CGPoint _posDrawerOpen;
    BOOL _isDrawerOpen;
    UIPanGestureRecognizer *_gestureRecognizerDrawer;
    long _frameCount;
    NSMutableDictionary *_shaders;
    UIActionSheet *_actionSheet;
}

@property (strong, nonatomic) GLKBaseEffect *effect;

- (void)setupGL;
- (void)tearDownGL;
- (BOOL)loadShaders;

@end

static const float DrawerRevealHeight = 20.0f;

@implementation NOCSketchViewController

@synthesize frameCount = _frameCount;

#pragma mark - Init

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if(self){
        [self initNOCSketchViewController];
    }
    return self;    
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if(self){
        [self initNOCSketchViewController];
    }
    return self;
}

- (void)initNOCSketchViewController
{
    _shaders = [NSMutableDictionary dictionaryWithCapacity:10];
}

#pragma mark - Memory

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

#pragma mark - Accessors

- (NOCShaderProgram *)shaderNamed:(NSString *)shaderName
{
    NOCShaderProgram *shader = [_shaders valueForKey:shaderName];
    if(!shader){
        NSLog(@"ERROR: Could not find shader with name %@", shaderName);
    }
    return shader;
}

- (void)addShader:(NOCShaderProgram *)shader named:(NSString *)shaderName
{
    [_shaders setValue:shader forKey:shaderName];
}

#pragma mark - View

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupGL];
    
    // Setup the GUI Drawer
    NSString *guiName = [self nibNameForControlGUI];
    if(guiName){
        
        _isDraggingDrawer = NO;
        _isDrawerOpen = NO;
        self.viewControls.hidden = YES;
        [self.view addSubview:self.viewControls];
        
        UIView *controlView = [[NSBundle mainBundle] loadNibNamed:guiName owner:self options:0][0];
        controlView.frame = self.viewControls.bounds;
        [self.viewControls insertSubview:controlView atIndex:0];
        
        // A gesture recognizer to handle opening/closing the drawer
        _gestureRecognizerDrawer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
        self.viewControls.gestureRecognizers = @[_gestureRecognizerDrawer];
    }
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UIBarButtonItem *actionItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                target:self
                                                                                action:@selector(buttonActionPressed:)];
    
    self.navigationItem.rightBarButtonItem = actionItem;
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self resize];
    [self repositionDrawer:YES];
    [self teaseDrawer];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_actionSheet dismissWithClickedButtonIndex:_actionSheet.cancelButtonIndex animated:NO];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self repositionDrawer:NO];
    [self resize];
}

#pragma mark - Accessors

- (NSString *)nibNameForControlGUI
{
    return nil;
}

#pragma mark - Gesture Recognizer

- (void)handleGesture:(UIPanGestureRecognizer *)gr
{
    BOOL shouldOpenDrawer = NO;
    BOOL shouldCloseDrawer = NO;
    CGPoint grPos = [gr locationInView:self.view];
    CGPoint grTrans = [gr translationInView:self.view];
    CGSize sizeDrawer = self.viewControls.frame.size;

    switch (gr.state) {
            
        case UIGestureRecognizerStateBegan:
            _isDraggingDrawer = NO;
            if(fabs(grTrans.y) > fabs(grTrans.x * 2)){
                // This is a vertical swipe
                _isDraggingDrawer = YES;
            }
            break;
        case UIGestureRecognizerStateChanged:
            
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if(_isDraggingDrawer){
                float minTravelDist = sizeDrawer.height * 0.25;
                shouldCloseDrawer = grTrans.y > minTravelDist;
                if(!shouldCloseDrawer){
                    shouldOpenDrawer = fabs(grTrans.y) > minTravelDist;
                }
                if(!shouldCloseDrawer && !shouldOpenDrawer){
                    if(_isDrawerOpen){
                        shouldOpenDrawer = YES;
                    }else{
                        shouldCloseDrawer = YES;
                    }
                }
            }
            _isDraggingDrawer = NO;
            break;
        default:
            break;
    }

    if(_isDraggingDrawer){
        
        self.viewControls.center = CGPointMake(_posDrawerClosed.x,
                                               MAX(grPos.y + (sizeDrawer.height*0.5),
                                                   _posDrawerOpen.y));
        
    }else{
        
        if(shouldCloseDrawer){
            [self closeDrawer];
        }else if(shouldOpenDrawer){
            [self openDrawer];
        }
    }
}

#pragma mark - Motion

- (GLKVector2)motionVectorFromManager:(CMMotionManager *)motionManager
{    
    CMDeviceMotion *motion = [motionManager deviceMotion];
    CMAcceleration gravity = motion.gravity;
    
    float halfWidth = 1;
    float halfHeight = 1 / _viewAspect;
    
    // Calibrate for the amount of tilt by eyeballing
    const static float GravityMultiplier = 2.0f;
    
    float x = gravity.x * halfWidth * GravityMultiplier;
    float y = gravity.y * halfHeight * GravityMultiplier;
    float swap = x;
    
    switch (self.interfaceOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            x = y;
            y = swap * -1;
            break;
        case UIInterfaceOrientationLandscapeRight:
            x = y * -1;
            y = swap;
            break;
        case UIInterfaceOrientationPortrait:
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            x = x * -1;
            y = y * -1;
            break;
    }
    
    return GLKVector2Make(x, y);
}

#pragma mark - View States

- (void)repositionDrawer:(BOOL)setViewCenter
{
    CGSize sizeView = self.view.frame.size;
    CGSize sizeViewDrawer = self.viewControls.frame.size;

    _posDrawerOpen = CGPointMake(sizeView.width * 0.5,
                                   sizeView.height - (sizeViewDrawer.height * 0.5));
    _posDrawerClosed = CGPointMake(sizeView.width * 0.5,
                                   sizeView.height + (sizeViewDrawer.height * 0.5) - DrawerRevealHeight);
    if(setViewCenter){
        self.viewControls.center = _posDrawerClosed;
        self.viewControls.hidden = NO;
    }    
}

- (void)closeDrawer
{
    [UIView animateWithDuration:0.25
                     animations:^{
                         self.viewControls.center = _posDrawerClosed;
                     }
                     completion:^(BOOL finished) {
                         _isDrawerOpen = NO;
                         self.buttonHideControls.layer.transform = CATransform3DMakeScale(1, 1, 1);
                     }];
}

- (void)openDrawer
{
    [UIView animateWithDuration:0.25
                     animations:^{
                         self.viewControls.center = _posDrawerOpen;
                     }
                     completion:^(BOOL finished) {
                         _isDrawerOpen = YES;
                         // Flip the toggle button so it's facing down
                         self.buttonHideControls.layer.transform = CATransform3DMakeScale(1, -1, 1);
                     }];
}

- (void)teaseDrawer
{
    [UIView animateWithDuration:0.35
                     animations:^{
                         self.viewControls.center = CGPointMake(_posDrawerClosed.x,
                                                                _posDrawerClosed.y - 50.0f);
                     }
                     completion:^(BOOL finished) {
                         [UIView animateWithDuration:0.25
                                               delay:0.3
                                             options:0
                                          animations:^{
                                              self.viewControls.center = _posDrawerClosed;
                                          } completion:^(BOOL finished) {
                                             //...
                                          }];
                     }];
}

#pragma mark - IBActions

- (IBAction)buttonHideControlsPressed:(id)sender
{
    if(_isDrawerOpen){
        [self closeDrawer];
    }else{
        [self openDrawer];
    }
}

static NSString *const NOCActionButtonTitleReadMore = @"Read About This Topic";
static NSString *const NOCActionButtonTitleViewCode = @"View Code";

- (IBAction)buttonActionPressed:(UIBarButtonItem *)sender
{
    if(_actionSheet){
        [_actionSheet dismissWithClickedButtonIndex:_actionSheet.cancelButtonIndex
                                           animated:NO];
    }
    _actionSheet = [[UIActionSheet alloc] initWithTitle:@"Online Resources"
                                               delegate:self
                                      cancelButtonTitle:@"Cancel"
                                 destructiveButtonTitle:nil
                                      otherButtonTitles:NOCActionButtonTitleReadMore,
                                                        NOCActionButtonTitleViewCode,
                                        nil];
    [_actionSheet showFromBarButtonItem:sender
                               animated:YES];
}

#pragma mark - UIActionSheet delegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(buttonIndex != [actionSheet cancelButtonIndex]){
        if([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:NOCActionButtonTitleReadMore]){
            [[UIApplication sharedApplication] openURL:self.sketch.URLReadMore];
        }else if([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:NOCActionButtonTitleViewCode]){
            [[UIApplication sharedApplication] openURL:self.sketch.URLCode];
        }
    }
    _actionSheet = nil;
}

#pragma mark - GL


- (void)loadGLContext
{
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [EAGLContext setCurrentContext:self.context];
    
}

- (void)setupGL
{
    _frameCount = 0;
    [self loadGLContext];
    [self resize];
    [self setup];
    [self loadShaders];
}

- (void)tearDownGL
{
    [self teardown];
    for(NSString *shaderName in _shaders){
        NOCShaderProgram *shader = [self shaderNamed:shaderName];
        [shader unload];
    }
    [EAGLContext setCurrentContext:self.context];
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    [self draw];
    _frameCount++;
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    for(NSString *shaderName in _shaders){
        
        NOCShaderProgram *shader = [self shaderNamed:shaderName];
        BOOL didLoad = [shader load];
        if(!didLoad){
            return NO;
        }

    }
    
    return YES;
}

#pragma mark - Subclass Loop

- (void)setup
{
    //..
}

- (void)update
{
    //...
}

- (void)resize
{
    _sizeView = self.view.frame.size;
    _viewAspect = _sizeView.width / _sizeView.height;
    
    for(int i=0;i<4;i++){
        _screen3DBillboardVertexData[i*3+0] = Square3DBillboardVertexData[i*3+0] * 2;
        _screen3DBillboardVertexData[i*3+1] = Square3DBillboardVertexData[i*3+1] * 2 / _viewAspect;
        _screen3DBillboardVertexData[i*3+2] = Square3DBillboardVertexData[i*3+2] * 2;
    }
}

- (void)draw
{
    //...
}

- (void)clear
{
    glClearColor(0,0,0,1);
    glClear(GL_COLOR_BUFFER_BIT);
}

- (void)teardown
{
    //...
}

@end
