//
//  WHC_KeyboardManager.swift
//  WHC_KeyboardManager
//
//  Created by WHC on 16/11/14.
//  Copyright © 2016年 WHC. All rights reserved.
//

//  Github <https://github.com/netyouli/WHC_KeyboardManager>

//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit

extension NSNotification.Name {
    /// 获取下一个编辑框视图的通知
    public static let NextFieldView: NSNotification.Name = NSNotification.Name(rawValue: "GetNextFieldViewNotification")
    /// 获取当前编辑框视图的通知
    public static let CurrentFieldView: NSNotification.Name = NSNotification.Name(rawValue: "GetCurrentFieldViewNotification")
    /// 获取上一个编辑框视图的通知
    public static let FrontFieldView: NSNotification.Name = NSNotification.Name(rawValue: "GetFrontFieldViewNotification")
}

public class WHC_KeyboardManager: NSObject,UITextFieldDelegate {
    
    /// 键盘头部视图配置类
    public class Configuration: NSObject {
        /// 获取移动视图的偏移回调块
        fileprivate var offsetBlock: ((_ field: UIView?) -> CGFloat)?
        /// 获取移动视图回调
        fileprivate var offsetViewBlock: ((_ field: UIView?) -> UIView?)?
        /// 存储键盘头视图
        fileprivate var headerView: UIView? = WHC_KeyboardHeaderView()
        /// 是否添加了监听滚动视图
        fileprivate var didObserveScrollView = false
        /// 是否启用键盘头部工具条
        public var enableHeader: Bool {
            set {
                if newValue {
                    if headerView == nil {
                        headerView = WHC_KeyboardHeaderView()
                    }
                }else {
                    headerView = nil
                }
            }
            
            get {
                return headerView != nil
            }
        }
        
        //MARK: - 自定义键盘配置回调 -
        /// 设置键盘挡住要移动视图的偏移量
        ///
        /// - parameter block: 回调block
        public func setOffset(block: @escaping ((_ field: UIView?) -> CGFloat)) {
            offsetBlock = block
        }
        
        /// 设置键盘挡住的Field要移动的视图
        ///
        /// - parameter block: 回调block
        public func setOffsetView(block: @escaping ((_ field: UIView?) -> UIView?)) {
            offsetViewBlock = block
        }
    }
    
    /// 当前控制器的键盘配置
    private(set) public var KeyboardConfiguration: Configuration?
    /// 监视控制器和配置集合
    private var KeyboardConfigurations = [String: Configuration]()
    /// 当前的输入视图(UITextView/UITextField)
    private(set) public var currentField: UIView!
    /// 上一个输入视图
    private(set) public var frontField: UIView!
    /// 下一个输入视图
    private(set) public var nextField: UIView!
    /// 要监视处理的控制器集合
    private var monitorViewControllers = [String]()
    /// 当前监视处理的控制器
    private weak var currentMonitorViewController: UIViewController!
    /// 设置移动的视图动画周期
    private lazy var moveViewAnimationDuration: TimeInterval = 0.5
    /// 键盘出现的动画周期
    private var keyboardDuration: TimeInterval?
    /// 存储键盘的frame
    private var keyboardFrame: CGRect! = CGRect.zero
    /// 监听UIScrollView内容偏移
    private let kContentOffset = "contentOffset"
    /// 是否已经显示了header
    private var didShowHeader = false
    /// 是否已经移除了键盘监听
    private var didRemoveKBObserve = false
    /// 初始化标示
    private let kNotInitValue: CGFloat = -888888.88
    /// 保存moveView初始y
    private lazy var initMoveViewY: CGFloat = self.kNotInitValue
    
    /// 单利对象
    public static var share: WHC_KeyboardManager {
        struct WHC_KeyboardManagerInstance {
            static let kbManager = WHC_KeyboardManager()
        }
        return WHC_KeyboardManagerInstance.kbManager
    }
    
    override init() {
        super.init()
        addKeyboardMonitor()
    }
    
    deinit {
        removeKeyboardObserver()
    }
    
    //MARK: - 私有方法 -
    private func addKeyboardMonitor() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notify:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notify:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(myTextFieldDidBeginEditing(notify:)), name: NSNotification.Name.UITextFieldTextDidBeginEditing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(myTextFieldDidEndEditing(notify:)), name: NSNotification.Name.UITextFieldTextDidEndEditing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(myTextFieldDidBeginEditing(notify:)), name: NSNotification.Name.UITextViewTextDidBeginEditing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(myTextFieldDidEndEditing(notify:)), name: NSNotification.Name.UITextViewTextDidEndEditing, object: nil)
    }
    
    /// 检查是否是系统的私有滚动类
    private func checkIsPrivateContainerClass(_ view: UIView) -> Bool {
        struct PrivateClass {
            static var UITableViewCellScrollViewClass: UIScrollView.Type? =   NSClassFromString("UITableViewCellScrollView") as? UIScrollView.Type
            static var UITableViewWrapperViewClass: UIView.Type? = NSClassFromString("UITableViewWrapperView") as? UIView.Type
            static var UIQueuingScrollViewClass: UIScrollView.Type? =   NSClassFromString("_UIQueuingScrollView") as? UIScrollView.Type
        }
        return !((PrivateClass.UITableViewWrapperViewClass == nil || view.isKind(of: PrivateClass.UITableViewWrapperViewClass!) == false) &&
            (PrivateClass.UITableViewCellScrollViewClass == nil || view.isKind(of: PrivateClass.UITableViewCellScrollViewClass!) == false) &&
            (PrivateClass.UIQueuingScrollViewClass == nil || view.isKind(of: PrivateClass.UIQueuingScrollViewClass!) == false))
        
    }
    
    /// 检查是否系统的私有输入类
    private func checkIsPrivateInputClass(_ view: UIView) -> Bool {
        struct PrivateClass {
            static var UISearchBarTextFieldClass: UITextField.Type? =   NSClassFromString("UISearchBarTextField") as? UITextField.Type
            static var UIAlertSheetTextFieldClass: UITextField.Type? =   NSClassFromString("UIAlertSheetTextField") as? UITextField.Type
            static var UIAlertSheetTextFieldClass_iOS8: UITextField.Type? =   NSClassFromString("_UIAlertControllerTextField") as? UITextField.Type
        }
        return !((PrivateClass.UISearchBarTextFieldClass == nil || view.isKind(of: PrivateClass.UISearchBarTextFieldClass!) == false) && (PrivateClass.UIAlertSheetTextFieldClass == nil || view.isKind(of: PrivateClass.UIAlertSheetTextFieldClass!) == false) && (PrivateClass.UIAlertSheetTextFieldClass_iOS8 == nil || view.isKind(of: PrivateClass.UIAlertSheetTextFieldClass_iOS8!) == false))
    }
    
    /// 动态扫描前后field
    private func scanFrontNextField() {
        func startScan(view: UIView) -> [UIView] {
            var subFields = [UIView]()
            if view.isUserInteractionEnabled && view.alpha != 0 && !view.isHidden {
                if view is UITextView {
                    if !subFields.contains(view) && (view as! UITextView).isEditable {
                            subFields.append(view)
                    }
                }else if view is UITextField {
                    if !subFields.contains(view) && (view as! UITextField).isEnabled && !checkIsPrivateInputClass(view) {
                        subFields.append(view)
                    }
                }else if view.subviews.count != 0 {
                    for subView in view.subviews {
                        subFields.append(contentsOf: startScan(view: subView))
                    }
                }
            }
            return subFields
        }
        var fields = startScan(view: getCurrentOffsetView())
        fields.sort { (field1, field2) -> Bool in
            let fieldConvertFrame1 = field1.convert(field1.bounds, to: currentMonitorViewController.view)
            let fieldConvertFrame2 = field2.convert(field1.bounds, to: currentMonitorViewController.view)
            let field1X = fieldConvertFrame1.minX
            let field1Y = fieldConvertFrame1.minY
            let field2X = fieldConvertFrame2.minX
            let field2Y = fieldConvertFrame2.minY
            return field1Y != field2Y ? field1Y < field2Y : field1X < field2X
        }
        frontField = nil;nextField = nil
        let index = fields.index(of: currentField)
        if index != nil {
            if index! > 0 {
                frontField = fields[index! - 1]
            }
            if index! < fields.count - 1 {
                nextField = fields[index! + 1]
            }
        }
    }
    
    /// 动态获取偏移视图
    private func getCurrentOffsetView() -> UIView {
        if let offsetView = KeyboardConfiguration?.offsetViewBlock?(currentField) {
            return offsetView
        }
        if currentField != nil {
        var superView = currentField
            while let tempSuperview = superView?.superview {
                if tempSuperview.isKind(of: UIScrollView.classForCoder()) ||
                    tempSuperview.isKind(of: UITableView.classForCoder()) ||
                    tempSuperview.isKind(of: UICollectionView.classForCoder()) {
                    if tempSuperview.isKind(of: UITextView.classForCoder()) == false && !checkIsPrivateContainerClass(tempSuperview) {
                        if (tempSuperview as! UIScrollView).contentSize.height > tempSuperview.frame.height && (tempSuperview as! UIScrollView).isScrollEnabled {
                            return tempSuperview
                        }
                    }
                }
                superView = tempSuperview
            }
        }
        return currentMonitorViewController.view
    }
    
    /// 动态更新键盘头部视图
    private func updateHeaderView(complete: (() -> Void)!) {
        let headerView: UIView! = KeyboardConfiguration?.headerView
        if headerView != nil {
            if keyboardFrame?.width == 0 {
                if headerView.superview != nil {
                    UIView.animate(withDuration: moveViewAnimationDuration, animations: { 
                        headerView.layer.transform = CATransform3DMakeTranslation(0, self.keyboardFrame.height + headerView.frame.height, 0)
                        }, completion: { (finished) in
                            headerView.layer.transform = CATransform3DIdentity
                            self.didShowHeader = false
                            headerView.removeFromSuperview()
                            complete?()
                    })
                }
            }else {
                let addHeaderViewConstraint = {(headerView: UIView) in
                    headerView.superview?.addConstraint(NSLayoutConstraint(item: headerView, attribute: NSLayoutAttribute.left, relatedBy: NSLayoutRelation.equal, toItem: headerView.superview!, attribute: NSLayoutAttribute.left, multiplier: 1, constant: 0))
                    
                    headerView.superview?.addConstraint(NSLayoutConstraint(item: headerView, attribute: NSLayoutAttribute.right, relatedBy: NSLayoutRelation.equal, toItem: headerView.superview!, attribute: NSLayoutAttribute.right, multiplier: 1, constant: 0))
                    
                    headerView.addConstraint(NSLayoutConstraint(item: headerView, attribute: NSLayoutAttribute.height, relatedBy: NSLayoutRelation.equal, toItem: nil, attribute: NSLayoutAttribute.notAnAttribute, multiplier: 1, constant: 44))
                    
                    headerView.superview?.addConstraint(NSLayoutConstraint(item: headerView, attribute: NSLayoutAttribute.lastBaseline, relatedBy: NSLayoutRelation.equal, toItem: headerView.superview!, attribute: NSLayoutAttribute.lastBaseline, multiplier: 1, constant: -self.keyboardFrame.height))
                }
                if headerView.superview == nil {
                    currentMonitorViewController.view.window?.addSubview(headerView)
                    if headerView.translatesAutoresizingMaskIntoConstraints {
                        headerView.translatesAutoresizingMaskIntoConstraints = false
                    }
                    addHeaderViewConstraint(headerView)
                }else {
                    if !headerView.translatesAutoresizingMaskIntoConstraints {
                        for constraint in headerView.superview!.constraints {
                            if constraint.firstItem === headerView {
                                headerView.superview?.removeConstraint(constraint)
                            }
                        }
                        addHeaderViewConstraint(headerView)
                    }
                }
                if !didShowHeader {
                    headerView.alpha = 0
                    let duration = keyboardDuration == nil ? 0.25 : keyboardDuration!
                    UIView.animate(withDuration: duration, delay: duration, options: UIViewAnimationOptions.curveEaseOut, animations: {
                            headerView.alpha = 1
                        }, completion: { (finished) in
                            self.didShowHeader = true
                            complete?()
                    })
                }
            }
        }else {
            complete?()
        }
    }
    
    /// 处理键盘出现时自动调整当前UI(输入视图不被遮挡)
    private func handleKeyboardDidShowToAdjust() {
        let headerView: UIView! = KeyboardConfiguration?.headerView
        let offsetBlock = KeyboardConfiguration?.offsetBlock
        if keyboardFrame != nil && keyboardFrame.height != 0 && currentField != nil {
            let moveView = getCurrentOffsetView()
            var moveScrollView: UIScrollView!
            if moveView is UITableView ||
                moveView is UIScrollView ||
                moveView is UICollectionView {
                moveScrollView = moveView as? UIScrollView
                if KeyboardConfiguration != nil && !KeyboardConfiguration!.didObserveScrollView {
                    KeyboardConfiguration!.didObserveScrollView = true
                    moveScrollView?.addObserver(self, forKeyPath: kContentOffset, options: NSKeyValueObservingOptions.new, context: nil)
                }
            }else {
                if initMoveViewY == kNotInitValue {
                    initMoveViewY = moveView.frame.origin.y
                }
            }
            headerView?.layoutIfNeeded()
            let convertView: UIView? = moveScrollView == nil ? currentMonitorViewController!.view : currentMonitorViewController!.view.window
            var convertRect = currentField.convert(currentField.bounds, to: convertView)
            if convertView!.frame.height < UIScreen.main.bounds.height && currentMonitorViewController.navigationController != nil {
                convertRect.origin.y += currentMonitorViewController.navigationController!.navigationBar.frame.height
            }
            let yOffset = convertRect.maxY - keyboardFrame!.minY
            let headerHeight: CGFloat = headerView != nil ? headerView.frame.height : 0
            var moveOffset: CGFloat = offsetBlock == nil ? headerHeight : offsetBlock!(currentField) + headerHeight
            
            if offsetBlock == nil && headerView == nil {
                if nextField != nil {
                    let nextFrame = nextField.convert(nextField.bounds, to: convertView)
                    moveOffset += nextFrame.maxY - convertRect.maxY
                }
            }
            if moveScrollView != nil {
                var sumOffsetY = moveScrollView.contentOffset.y + moveOffset + yOffset
                sumOffsetY = max(sumOffsetY, -moveScrollView.contentInset.top)
                UIView.animate(withDuration: moveViewAnimationDuration, animations: {
                    moveScrollView.contentOffset = CGPoint(x: moveScrollView.contentOffset.x, y: sumOffsetY)
                    }, completion: { (success) in})
            }else {
                var sumOffsetY = -(moveOffset + yOffset)
                sumOffsetY = min(0, sumOffsetY)
                var moveViewFrame = moveView.frame
                moveViewFrame.origin.y = sumOffsetY
                UIView.animate(withDuration: moveViewAnimationDuration, animations: {
                    moveView.frame = moveViewFrame
                })
            }
        }
    }
    
    private func setCurrentMonitorViewController() {
        let topViewController = self.whc_CurrentViewController()
        currentMonitorViewController = nil
        if topViewController != nil && monitorViewControllers.contains(topViewController!.description) {
            currentMonitorViewController = topViewController
            KeyboardConfiguration = KeyboardConfigurations[currentMonitorViewController.description]
        }
    }
    
    //MARK: - 公开接口Api -

    /// 设置要监听处理键盘的控制器
    ///
    /// - parameter vc: 设置要监听的控制器
    /// return 返回默认的键盘头部配置对象
    @discardableResult
    public func addMonitorViewController(_ vc:UIViewController) -> WHC_KeyboardManager.Configuration {
        let configuration = WHC_KeyboardManager.Configuration()
        self.KeyboardConfiguration = configuration
        KeyboardConfigurations.updateValue(configuration, forKey: vc.description)
        if !monitorViewControllers.contains(vc.description) {
            monitorViewControllers.append(vc.description)
        }
        if didRemoveKBObserve {
            addKeyboardMonitor()
            didRemoveKBObserve = false
        }
        return configuration
    }
    
    /// 移除监听的控制器对象
    ///
    /// - parameter vc: 要移除的控制器
    public func removeMonitorViewController(_ vc: UIViewController?) -> Void {
        if vc != nil {
            KeyboardConfigurations.removeValue(forKey: vc!.description)
            if monitorViewControllers.contains(vc!.description) {
                monitorViewControllers.remove(at: monitorViewControllers.index(of: vc!.description)!)
            }
        }
    }
    
    
    /// 移除键盘管理监听
    public func removeKeyboardObserver() {
        KeyboardConfigurations.removeAll()
        monitorViewControllers.removeAll()
        NotificationCenter.default.removeObserver(self)
        didRemoveKBObserve = true
    }
    
    //MARK: - 发送通知 -
    private func sendFieldViewNotify() {
        if KeyboardConfiguration?.headerView != nil {
            NotificationCenter.default.post(name: NSNotification.Name.CurrentFieldView, object: currentField)
            NotificationCenter.default.post(name: NSNotification.Name.NextFieldView, object: nextField)
            NotificationCenter.default.post(name: NSNotification.Name.FrontFieldView, object: frontField)
        }
    }
    
    // MARK: - 键盘监听处理 -
    
    @objc private func keyboardWillShow(notify: Notification) {
        if currentField == nil {
            setCurrentMonitorViewController()
        }
        if currentMonitorViewController == nil {return}
        let userInfo = notify.userInfo
        keyboardFrame = (userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        keyboardDuration = (userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue
        updateHeaderView(complete: nil)
        handleKeyboardDidShowToAdjust()
    }
    
    @objc private func keyboardWillHide(notify: Notification) {
        if currentMonitorViewController == nil {return}
        keyboardFrame?.size.width = 0
        keyboardDuration = 0
        updateHeaderView(complete: nil)
        keyboardFrame = CGRect.zero
        let moveView = getCurrentOffsetView()
        if moveView is UITableView ||
            moveView is UIScrollView ||
            moveView is UICollectionView {
            let scrollMoveView = moveView as? UIScrollView
            if scrollMoveView != nil {
                if KeyboardConfiguration != nil && KeyboardConfiguration!.didObserveScrollView {
                    KeyboardConfiguration!.didObserveScrollView = false
                    scrollMoveView!.removeObserver(self, forKeyPath: kContentOffset)
                }
                UIView.animate(withDuration: moveViewAnimationDuration, animations: {
                    if scrollMoveView!.contentOffset.y < -scrollMoveView!.contentInset.top {
                        scrollMoveView!.contentOffset = CGPoint(x: (scrollMoveView?.contentOffset.x)!, y: -scrollMoveView!.contentInset.top)
                    }else if scrollMoveView!.contentOffset.y > (scrollMoveView!.contentSize.height - scrollMoveView!.bounds.height + scrollMoveView!.contentInset.bottom) {
                        if scrollMoveView!.contentSize.height == 0 {
                            scrollMoveView!.contentOffset = CGPoint(x: scrollMoveView!.contentOffset.x, y: -scrollMoveView!.contentInset.top)
                        }else {
                            scrollMoveView!.contentOffset = CGPoint(x: (scrollMoveView?.contentOffset.x)!, y: (scrollMoveView!.contentSize.height - scrollMoveView!.bounds.height + scrollMoveView!.contentInset.bottom))
                        }
                    }
                })
            }
        }else {
            var moveViewFrame = moveView.frame
            moveViewFrame.origin.y = initMoveViewY
            /**** Give up the following method ***/
            /*if currentMonitorViewController.view === moveView && currentMonitorViewController.navigationController != nil && (currentMonitorViewController.edgesForExtendedLayout == .none || !currentMonitorViewController.navigationController!.navigationBar.isTranslucent) && !currentMonitorViewController.navigationController!.isNavigationBarHidden {
                moveViewFrame.origin.y = currentMonitorViewController.navigationController!.navigationBar.frame.maxY
            }else {
                moveViewFrame.origin.y = 0
            }*/
            initMoveViewY = kNotInitValue
            UIView.animate(withDuration: moveViewAnimationDuration, animations: {
                moveView.frame = moveViewFrame
            })
        }
    }

    //MARK: - 滑动监听 -
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if currentMonitorViewController == nil {return}
        if keyPath != nil && keyPath! == kContentOffset && currentField != nil {
            let contentOffset = (change?[.newKey] as? NSValue)?.cgPointValue
            if contentOffset != nil {
                let scrollView = object as? UIScrollView
                if scrollView != nil && (scrollView!.isDragging || scrollView!.isDecelerating) {
                    let convertRect = currentField.convert(currentField.bounds, to: currentMonitorViewController!.view.window!)
                    let yOffset = convertRect.maxY - keyboardFrame!.minY
                    if yOffset > 0 || convertRect.minY < 0 {
                        if currentField is UITextView {
                            (currentField as! UITextView).resignFirstResponder()
                        }else if currentField is UITextField {
                            (currentField as! UITextField).resignFirstResponder()
                        }else {
                            currentField.endEditing(true)
                        }
                    }
                }
            }
        }
    }
    
    //MARK: - 编辑通知 -
    @objc private func myTextFieldDidBeginEditing(notify: Notification) {
        setCurrentMonitorViewController()
        if currentMonitorViewController != nil {
            currentField = notify.object as? UIView
            scanFrontNextField()
            sendFieldViewNotify()
            handleKeyboardDidShowToAdjust()
        }
    }
    
    @objc private func myTextFieldDidEndEditing(notify: Notification) {
        let fieldView = notify.object as? UIView
        if fieldView === currentField {
            currentField = nil
            nextField = nil
            frontField = nil
            currentMonitorViewController = nil
        }
    }
}
