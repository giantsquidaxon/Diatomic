//
//  Diatom.m
//  Diatomic
//
//  Created by Richard Smith on 02/02/2014.
//  Copyright (c) 2014 Richard Smith. All rights reserved.
//

#import "Diatom.h"
#import "SoundManager.h"
static const NSUInteger maxConnections = 2;

@implementation Diatom{
    bool isRefractory;
    NSMutableArray *connections;
    NSMutableArray *joints;
}

@synthesize kind;

-(id)init
{
    NSString *diatomName;
    kind = arc4random() % 5;
    //kind = 0;
    switch (kind) {
        case 0:
            diatomName = @"Diatom1";
            break;
        case 1:
            diatomName = @"Diatom2";
            break;
        case 2:
            diatomName = @"Diatom3";
            break;
        case 3:
            diatomName = @"Diatom4";
            break;
        case 4:
            diatomName = @"Diatom5";
            break;
        default:
            diatomName = @"Diatom2";
            break;
    }
    if (self = [super initWithImageNamed:diatomName]){
        self.size = CGSizeMake(self.size.width / 2.0, self.size.height / 2.0);
        self.physicsBody = [SKPhysicsBody bodyWithCircleOfRadius:self.size.width / 2.2];
        self.physicsBody.contactTestBitMask = diatomCollisonMask;
        self.physicsBody.collisionBitMask = diatomCollisonMask | borderCollisonMask | deadDiatomCollisonMask;
        self.physicsBody.categoryBitMask = diatomCollisonMask;
        isRefractory = NO;
        connections = [[NSMutableArray alloc] init];
        joints = [[NSMutableArray alloc] init];
    }
    return self;
}

-(void)brownianKick
{
    // Scale brownian kicks proportionally to the perimeter
    CGFloat scaling = self.size.width / 100;
    CGVector kick = CGVectorMake((0.25 - (arc4random()%1000 / 2000.0)) * scaling, (0.25 - (arc4random()%1000 / 2000.0)) * scaling);
    [self.physicsBody applyImpulse:kick];
}

-(void)didCollide
{
    // Return if refractory from another collision
    if (isRefractory) return;
    
    // Flash red
    self.color = [SKColor redColor];
    self.colorBlendFactor = 0.0;
    [self runAction:[SKAction colorizeWithColorBlendFactor:0.3 duration:0.2]
            withKey:@"redFlash"];
    
    // Play a note
    [[SoundManager theSoundManager] playNote:kind];
    
    // Become refractory for short period
    isRefractory = YES;
    [self runAction:[SKAction sequence:@[[SKAction waitForDuration:refractoryPeriod],
                                         [SKAction performSelector:@selector(becomeUnrefractory) onTarget:self]]]];
    
    // End red flash by fading back to normal
    [self runAction:[SKAction sequence:@[[SKAction waitForDuration:0.2],
                                         [SKAction colorizeWithColorBlendFactor:0.0 duration:0.5]]]];

}

-(void)didMoveApart
{
}

-(void)connectToDiatom:(Diatom *)d withContactPoint:(CGPoint)p
{
    // Can both parties link up?
    if ([self canConnectToDiatom:d] && [d canConnectToDiatom:self])
    {

        // Add a physics joint
        CGPoint centreA = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));
        CGPoint centreB = CGPointMake(CGRectGetMidX(d.frame), CGRectGetMidY(d.frame));

        SKPhysicsJointSpring *newJoin = [SKPhysicsJointSpring jointWithBodyA:self.physicsBody bodyB:d.physicsBody anchorA:centreA anchorB:centreB];
        [self.scene.physicsWorld addJoint:newJoin];
        
        // Make two-way connection
        [self storeConnectionToDiatom:d withJoint:newJoin];
    }
}

-(void)storeConnectionToDiatom:(Diatom *)d withJoint:(SKPhysicsJoint *)j
{
    // Return if we're already hooked up
    if ([self isDirectlyConnectedToDiatom:d]) return;
    
    // Add connections and joint
    [connections addObject:d];
    [joints addObject:j];
    
    // Make a reciprocal connection in the other diatom
    [d storeConnectionToDiatom:self withJoint:j];
    
    //if connections are maxed out, go dead, and set a timer for chain breaking
    if ([connections count] == maxConnections){
        [self becomeDead];
        CGFloat timeUntilSplit = log( 1 - arc4random()%1000 / 1000.0 ) / (-dissociationConstant);
        NSLog(@"Link with time to live: %f", timeUntilSplit);
        [self runAction:[SKAction sequence:@[[SKAction waitForDuration:timeUntilSplit],
                                             [SKAction performSelector:@selector(splitChain) onTarget:self]]]];
    }
    
}

-(void)splitChain
{
    // Must be inside a chain
    if ([connections count] < 2) return;
    
    // Pick a link at random and break it
    Diatom *d = connections[ arc4random() % maxConnections ];
    [self severConnectionWithDiatom:d];
}

-(void)severConnectionWithDiatom:(Diatom *)d
{
    // Return if we've already disconnected
    if (![self isDirectlyConnectedToDiatom:d]) return;
    
    // Remove connection
    NSUInteger index= [connections indexOfObject:d];
    [connections removeObjectAtIndex:index];
    
    // Remove joint
    SKPhysicsJoint *joint = joints[index];
    [self.scene.physicsWorld removeJoint:joint];
    [joints removeObjectAtIndex:index];
    
    // Become alive again so we can join in with making chains
    [self becomeAlive];
    

    
    
    // Do same in other diatom
    [d severConnectionWithDiatom:self];
}

-(bool)isDirectlyConnectedToDiatom:(Diatom *)d
{
    return ([connections indexOfObject:d] != NSNotFound);
}

-(bool)isConnectedToDiatom:(Diatom *)d
{
    return [self areNeighboursConnectedToDiatom:d comingFromDiatom:self];
}

-(bool)areNeighboursConnectedToDiatom:(Diatom *)d comingFromDiatom:(Diatom *)prev
{
    // Return if this is the node we're looking for
    bool isConnected = d == self;
    if (isConnected) return isConnected;
    
    // Otherwise ask each neighbour (apart from the one we came from) if it's d
    for (Diatom *neighbour in connections) {
        // Skip if we're going back on ourselves
        if (neighbour != prev){
            isConnected |= [neighbour areNeighboursConnectedToDiatom:d comingFromDiatom:self];
        }
    }
    
    return isConnected;
}

-(bool)canConnectToDiatom:(Diatom *)d
{
    // Make sure we haven't exceeded maxConnections, they're the same kind, and they're not already connected.
    bool freeConnections = [connections count] < maxConnections;
    bool sameKind = self.kind == d.kind;
    bool isntConnectedAlready = ![self isConnectedToDiatom:d];
    
    return (freeConnections & sameKind & isntConnectedAlready);
    
}


#pragma mark state transitions
// Move into inert state
-(void)becomeDead
{
    [self removeAllActions];
    isRefractory = YES;
#ifdef DEBUG_COLORING
    self.colorBlendFactor = 1.0;
    self.color = [SKColor blueColor];
#endif
    self.physicsBody.contactTestBitMask = 0;
    self.physicsBody.categoryBitMask = deadDiatomCollisonMask;
}

// Move into state just prior to coming to life
// This will cause an alive cell to become temporarily dead
-(void)becomeAlive
{
    isRefractory = YES;
#ifdef DEBUG_COLORING
    self.colorBlendFactor = 1.0;
    self.color = [SKColor greenColor];
#endif

    self.physicsBody.contactTestBitMask = 0;
    self.physicsBody.categoryBitMask = deadDiatomCollisonMask;
    
    // Become unrefractory after refractory period
    [self runAction:[SKAction sequence:@[[SKAction waitForDuration:refractoryAfterSplitting],
                                         [SKAction performSelector:@selector(becomeFullyAlive) onTarget:self]]]];
    
}

// Become an alive cell
-(void)becomeFullyAlive
{
    self.physicsBody.contactTestBitMask = diatomCollisonMask;
    self.physicsBody.categoryBitMask = diatomCollisonMask;
    [self becomeUnrefractory];
}

// End refractory period
-(void)becomeUnrefractory
{
    self.color = [SKColor clearColor];
    self.colorBlendFactor = 0.0;
    isRefractory = NO;
}

@end