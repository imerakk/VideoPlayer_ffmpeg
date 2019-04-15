//
//  ViewController.m
//  VideoPlayer
//
//  Created by liuchunxi on 2019/3/29.
//  Copyright © 2019年 imera. All rights reserved.
//

#import "ViewController.h"
#import "GTVideoPlayerViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(100, 100, 200, 70);
    [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btn setTitle:@"play" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
}

- (void)play {
//    NSString *filePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"test.flv"];
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"flv"];
    GTVideoPlayerViewController *player = [GTVideoPlayerViewController viewControllerWithFilePath:filePath contentFrame:self.view.bounds parameters:nil];
    [self.navigationController pushViewController:player animated:YES];
}


@end
