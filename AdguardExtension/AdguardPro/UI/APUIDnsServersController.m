/**
    This file is part of Adguard for iOS (https://github.com/AdguardTeam/AdguardForiOS).
    Copyright © Adguard Software Limited. All rights reserved.
 
    Adguard for iOS is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
 
    Adguard for iOS is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
 
    You should have received a copy of the GNU General Public License
    along with Adguard for iOS.  If not, see <http://www.gnu.org/licenses/>.
 */


#import "APUIDnsServersController.h"
#import "APVPNManager.h"
#import "ACommons/ACSystem.h"
#import "ACommons/ACLang.h"
#import "APDnsServerObject.h"
#import "APUIDnsServerDetailController.h"
#import "ACNIPUtils.h"
#import "AEUICustomTextEditorController.h"
#import "APSharedResources.h"
#import "AERDomainFilterRule.h"
#import "AEUIUtils.h"

#define CHECKMARK_NORMAL_DISABLE        @"table-empty"
#define CHECKMARK_NORMAL_ENABLE         @"table-checkmark"

#define DNS_SERVER_SECTION_INDEX        1
#define DNS_SYSTEM_DEFAULT_SECTION_INDEX   0
#define DNS_CRYPT_SERVER_SECTION_INDEX        2

#define DNS_SERVER_DETAIL_SEGUE         @"dnsServerDetailSegue"
#define DNS_CRYPT_SERVER_DETAIL_SEGUE         @"dnsCryptServerDetailSegue"

#define DNS_CHECK_DISABLED_COLOR        [UIColor grayColor]

/////////////////////////////////////////////////////////////////////
#pragma mark - APUIDnsServersController

@interface APUIDnsServersController()

@end

@implementation APUIDnsServersController {
    
    id _observer;
    
    NSArray <APDnsServerObject *> *_dnsServers;
    NSArray <APDnsServerObject *> *_dnsCryptServers;
}

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    self.reloadTableViewRowAnimation = UITableViewRowAnimationAutomatic;
    
    // tunning accessibility
    self.addCustomCell.accessibilityTraits |= UIAccessibilityTraitButton;
    self.systemDefaultCell.accessibilityTraits |= UIAccessibilityTraitButton;
    //--------------
    
    [self attachToNotifications];
    
    APVPNManager *manager = [APVPNManager singleton];
    
    _dnsServers = manager.remoteDnsServers;
    _dnsCryptServers = manager.remoteDnsCryptServers;
    
    APDnsServerObject *systemDefault = _dnsServers[0];
    self.systemDefaultCell.textLabel.text = systemDefault.serverName;
    self.systemDefaultCell.detailTextLabel.text = systemDefault.serverDescription;
    [_dnsServers enumerateObjectsUsingBlock:^(APDnsServerObject * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if (idx) {
            [self internalInsertDnsServer:obj atIndex:idx section:DNS_SERVER_SECTION_INDEX];
        }
    }];
    
    [_dnsCryptServers enumerateObjectsUsingBlock:^(APDnsServerObject * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        [self internalInsertDnsServer:obj atIndex:idx section:DNS_CRYPT_SERVER_SECTION_INDEX];
    }];
    
    
    [self reloadDataAnimated:NO];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self updateStatuses];
    });
    
    [self attachToNotifications];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self updateStatuses];
    });
    
}

- (void)viewWillAppear:(BOOL)animated {
    
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    
    [super viewDidAppear:animated];
    
    if(![ACNIPUtils isIpv4Available] && [ACNIPUtils isIpv6Available]) {
        [ACSSystemUtils showSimpleAlertForController:self withTitle:ACLocalizedString(@"common_warning_title", @"(APUIAdguardDNSController) PRO version. Alert title. On warning.") message:ACLocalizedString(@"ipv6_network_connection", @"(APUIAdguardDNSController) Alert message. When custom dns not available.")];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    
}

- (void)dealloc{
    
    if (_observer) {
        [[NSNotificationCenter defaultCenter] removeObserver:_observer];
    }
}

/////////////////////////////////////////////////////////////////////
#pragma mark Actions


/////////////////////////////////////////////////////////////////////
#pragma mark Properties and public methods


- (void)addDnsServer:(APDnsServerObject *)serverObject {
    
    if (serverObject) {
        
        if ([[APVPNManager singleton] addRemoteDnsServer:serverObject]) {
        
            if(serverObject.isDnsCrypt.boolValue) {
                _dnsCryptServers = APVPNManager.singleton.remoteDnsCryptServers;
                [self internalInsertDnsServer:serverObject atIndex:(_dnsCryptServers.count - 1) section:DNS_CRYPT_SERVER_SECTION_INDEX];
            }
            else {
                _dnsServers = APVPNManager.singleton.remoteDnsServers;
                [self internalInsertDnsServer:serverObject atIndex:(_dnsServers.count - 1) section:DNS_SERVER_SECTION_INDEX];
            }
            
            [self reloadDataAnimated:YES];
            
            [self updateStatuses];
        }
    }
}

- (void)removeDnsServer:(APDnsServerObject *)serverObject {
    
    if (serverObject) {
        
        NSUInteger index = serverObject.isDnsCrypt.boolValue ?  [_dnsCryptServers indexOfObject:serverObject] :
                                                                [_dnsServers indexOfObject:serverObject];
        
        if (index == NSNotFound) {
            return;
        }
        
        if(!serverObject.isDnsCrypt.boolValue) {
            // because from second server
            index --;
        }
        
        if ([[APVPNManager singleton] removeRemoteDnsServer:serverObject]) {
            
            NSIndexPath *indexPath;
            
            if(serverObject.isDnsCrypt.boolValue) {
                indexPath = [NSIndexPath indexPathForRow:index inSection: DNS_CRYPT_SERVER_SECTION_INDEX];
                _dnsCryptServers = APVPNManager.singleton.remoteDnsCryptServers;
            }
            else {
                indexPath = [NSIndexPath indexPathForRow:index inSection: DNS_SERVER_SECTION_INDEX];
                _dnsServers = APVPNManager.singleton.remoteDnsServers;
            }
            
            [self removeCellAtIndexPath:indexPath];
            
            [self reloadDataAnimated:YES];
            
            [self updateStatuses];
        }
    }
}

- (void)modifyDnsServer:(APDnsServerObject *)serverObject {
    
    if (serverObject) {
        
        NSUInteger index = serverObject.isDnsCrypt.boolValue ?  [_dnsCryptServers indexOfObject:serverObject] :
                                                                [_dnsServers indexOfObject:serverObject];
        
        if (index == NSNotFound) {
            return;
        }
        
        if(!serverObject.isDnsCrypt.boolValue) {
            // because from second server
            index --;
        }
        
        if ([[APVPNManager singleton] resetRemoteDnsServer:serverObject]) {
            
            NSIndexPath *indexPath;
            
            if(serverObject.isDnsCrypt.boolValue) {
                _dnsCryptServers = APVPNManager.singleton.remoteDnsCryptServers;
                
                indexPath = [NSIndexPath indexPathForRow:index inSection:DNS_CRYPT_SERVER_SECTION_INDEX];
            }
            else {
                _dnsServers = APVPNManager.singleton.remoteDnsServers;
                
                indexPath = [NSIndexPath indexPathForRow:index inSection:DNS_SERVER_SECTION_INDEX];
            }
            
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            cell.textLabel.text = serverObject.serverName;
            cell.detailTextLabel.text = serverObject.serverDescription;
        }
    }
}

/////////////////////////////////////////////////////////////////////
#pragma mark Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    BOOL dnsDetails = [segue.identifier isEqualToString:DNS_SERVER_DETAIL_SEGUE];
    BOOL dnsCryptDetails = [segue.identifier isEqualToString:DNS_CRYPT_SERVER_DETAIL_SEGUE];
    
    if (dnsDetails || dnsCryptDetails) {
        
        APUIDnsServerDetailController *destination = (APUIDnsServerDetailController *)[(UINavigationController *)[segue destinationViewController]
                                                                                       topViewController];
        
        destination.delegate = self;
        
        if ([sender isKindOfClass:[APDnsServerObject class]]) {
            
            APDnsServerObject *server = sender;
            
            destination.serverObject = server;
        }
        
        destination.dnsCrypt = dnsCryptDetails;
    }
}

/////////////////////////////////////////////////////////////////////
#pragma mark  Table Delegate Methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if(indexPath.section == DNS_SERVER_SECTION_INDEX || indexPath.section == DNS_SYSTEM_DEFAULT_SECTION_INDEX ||
       indexPath.section == DNS_CRYPT_SERVER_SECTION_INDEX) {
        
        APDnsServerObject *selectedServer = [self remoteDnsServerAtIndexPath:indexPath];
        
        if (selectedServer) {
            
            APVPNManager.singleton.activeRemoteDnsServer = selectedServer;
            DDLogInfo(@"(APUIDnsServersController) Set Active Remote DNS Server to: %@", selectedServer.serverName);
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [self selectActiveDnsServer:selectedServer];
                APVPNManager.singleton.enabled = YES;
            });
        }
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(nonnull NSIndexPath *)indexPath {
    
    APDnsServerObject *selectedServer = [self remoteDnsServerAtIndexPath:indexPath];
    
    if (selectedServer) {
        
        [self performSegueWithIdentifier:DNS_SERVER_DETAIL_SEGUE sender:selectedServer];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(nonnull UIView *)view forSection:(NSInteger)section {
    
    // tunning accessibility
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    
    footer.isAccessibilityElement = NO;
    footer.textLabel.isAccessibilityElement = NO;
    footer.detailTextLabel.isAccessibilityElement = NO;
    
    if (section == DNS_SYSTEM_DEFAULT_SECTION_INDEX) {
        self.systemDefaultCell.accessibilityHint = footer.textLabel.text;
    }
}

/////////////////////////////////////////////////////////////////////
#pragma mark  Helper Methods (Private)



- (void)attachToNotifications{
    
    _observer = [[NSNotificationCenter defaultCenter]
                 addObserverForName:APVpnChangedNotification
                 object: nil
                 queue:nil
                 usingBlock:^(NSNotification *_Nonnull note) {
                     
                     // When configuration is changed
                     
                     [self updateStatuses];
                 }];
}

- (void)updateStatuses{
    
    APVPNManager *manager = [APVPNManager singleton];
    
    [self selectActiveDnsServer:manager.activeRemoteDnsServer];
    
    if (_dnsServers.count < manager.maxCountOfRemoteDnsServers) {
        
        self.addCustomCell.userInteractionEnabled = YES;
        self.addCustomCell.textLabel.enabled = YES;
    }
    else {
        
        self.addCustomCell.userInteractionEnabled = NO;
        self.addCustomCell.textLabel.enabled = NO;
    }
    
    [self.logSwitch setOn:manager.dnsRequestsLogging animated:YES];
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        
        NSUInteger blacklistDomainsCount = APSharedResources.blacklistDomains.count;
        NSUInteger whitelistDomainsCount = APSharedResources.whitelistDomains.count;
        
        dispatch_async(dispatch_get_main_queue(), ^{
           
            self.blacklistCell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", blacklistDomainsCount];
            self.whitelistCell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", whitelistDomainsCount];
        });
        
    });
    
    if (manager.lastError) {
        [ACSSystemUtils
         showSimpleAlertForController:self
         withTitle:ACLocalizedString(@"common_error_title",
                                     @"(APUIAdguardDNSController) PRO version. Alert title. On error.")
         message:manager.lastError.localizedDescription];
    }
}

- (void)internalInsertDnsServer:(APDnsServerObject *)serverObject atIndex:(NSUInteger)index section:(NSUInteger)section{
    
    if(section == DNS_SERVER_SECTION_INDEX) {
        // because from second server
        index--;
    }
    
    UITableViewCell *templateCell = self.remoteDnsServerTemplateCell;
    UITableViewCell *newCell = [AEUIUtils createCellByTemplate:templateCell style:UITableViewCellStyleSubtitle];
    
    newCell.tag = index;
    
    newCell.textLabel.text = serverObject.serverName;
    newCell.detailTextLabel.text = serverObject.serverDescription;
    newCell.imageView.image= [UIImage imageNamed:CHECKMARK_NORMAL_DISABLE];
    if (serverObject.editable) {
        newCell.accessoryType = UITableViewCellAccessoryDetailButton;
    }
    
    // tunning accessibility
    newCell.accessibilityTraits |= UIAccessibilityTraitButton;
    //---------------
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:section];
    [self insertCell:newCell atIndexPath:indexPath];
}

- (APDnsServerObject *)remoteDnsServerAtIndexPath:(NSIndexPath *)indexPath {
    
    if(indexPath.section == DNS_CRYPT_SERVER_SECTION_INDEX) {
        
        return indexPath.row < _dnsCryptServers.count ? _dnsCryptServers[indexPath.row] : nil;
    }
    
    NSInteger index = indexPath.row;
    
    if (indexPath.section == DNS_SERVER_SECTION_INDEX) {
        // because from second server
        index ++;
    }
    
    if (index < _dnsServers.count) {
        
        return _dnsServers[index];
    }
    
    return nil;
}

- (void)selectActiveDnsServer:(APDnsServerObject *)activeDnsServer {
    
    [self setCell:self.systemDefaultCell selected: [activeDnsServer.tag isEqualToString:APDnsServerTagLocal]];
    
    for (int i = 1; i < _dnsServers.count; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(i - 1) inSection:DNS_SERVER_SECTION_INDEX];
        UITableViewCell *cell = [self tableView:self.tableView cellForRowAtIndexPath:indexPath];
        
        [self setCell:cell selected: [activeDnsServer isEqual:_dnsServers[i]]];
    }
    
    for(int i = 0; i < _dnsCryptServers.count; ++i) {
        
        
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:DNS_CRYPT_SERVER_SECTION_INDEX];
        UITableViewCell *cell = [self tableView:self.tableView cellForRowAtIndexPath:indexPath];
        
        [self setCell:cell selected: [activeDnsServer isEqual:_dnsCryptServers[i]]];
    }
}

- (void) setCell:(UITableViewCell*) cell selected:(BOOL) selected {
    
    if(selected) {
        
        cell.imageView.image = [UIImage imageNamed:CHECKMARK_NORMAL_ENABLE];
        cell.accessibilityTraits |= UIAccessibilityTraitSelected;
        
        //cell.imageView.tintColor = self.proStatusSwitch.isOn ? cell.tintColor : DNS_CHECK_DISABLED_COLOR;
    }
    else {
        
        cell.imageView.image = [UIImage imageNamed:CHECKMARK_NORMAL_DISABLE];
        cell.accessibilityTraits &= ~UIAccessibilityTraitSelected;
    }
}

@end
