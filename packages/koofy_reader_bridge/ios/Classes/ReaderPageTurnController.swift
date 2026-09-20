import UIKit

/// UIKit owns the curved paper surface and interactive corner deformation.
/// This controller owns only page-side identity and completion/cancellation.
@MainActor
final class ReaderPageTurnController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    let frames: ReaderPageFrames
    var onBegin: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: ((ReaderPageFrame) -> Void)?
    private(set) var isTurning = false
    private var invalidated = false
    private let pageController: UIPageViewController
    private var faces: [Int: ReaderPageFaceController] = [:]
    private let background: UIColor
    private var touchView: ReaderTurnTouchView { view as! ReaderTurnTouchView }
    private var isSpread: Bool { frames.current.columns == 2 }
    private var directionSign: Int { frames.rightToLeft ? -1 : 1 }

    init(frames: ReaderPageFrames, background: UIColor) {
        self.frames = frames
        self.background = background
        let spine: UIPageViewController.SpineLocation = frames.current.columns == 2
            ? .mid : frames.rightToLeft ? .max : .min
        pageController = UIPageViewController(transitionStyle: .pageCurl,
            navigationOrientation: .horizontal, options: [.spineLocation: NSNumber(value: spine.rawValue)])
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frames:background:)") }

    override func loadView() { view = ReaderTurnTouchView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.accessibilityElementsHidden = true // The real EPUB remains accessible.
        touchView.isBusy = { [weak self] in self?.isTurning ?? false }
        touchView.canStart = { [weak self] point in
            guard let self, !self.invalidated else { return false }
            let edge = min(80, self.view.bounds.width * 0.2)
            let physicalForward = point.x > self.view.bounds.midX
            let forward = self.frames.rightToLeft ? !physicalForward : physicalForward
            return (point.x < edge || point.x > self.view.bounds.width - edge) &&
                (forward ? self.frames.next != nil : self.frames.previous != nil)
        }
        touchView.willReceiveTouch = { [weak self] in self?.revealForTouch() }
        addChild(pageController)
        pageController.view.frame = view.bounds
        pageController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageController.view.backgroundColor = .clear
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        pageController.dataSource = self
        pageController.delegate = self
        installSource()
        showImages(false)
    }

    private func installSource() {
        // Seed the edge spine with its one visible face, then enable a real
        // reverse side for gesture/animated transitions. The explicit order
        // avoids UIKit's different initial-versus-animated cardinality rules.
        pageController.isDoubleSided = isSpread
        pageController.setViewControllers(pair(at: 0), direction: .forward, animated: false)
        pageController.isDoubleSided = true
    }

    /// A single viewport consumes one logical step, although UIKit's
    /// double-sided presentation consumes front/back controller pairs.
    /// The back and underlying face preview the same destination viewport.
    /// A spread consumes its two actual column slots.
    private func face(at index: Int) -> ReaderPageFaceController? {
        if let existing = faces[index] { return existing }
        let pairIndex = Int(floor(Double(index) / 2))
        let side = index - pairIndex * 2
        let offset = pairIndex * directionSign
        guard let frame = frames.frame(at: offset) else { return nil }
        let image: UIImage
        if isSpread {
            guard let cg = frame.image.cgImage,
                  let crop = cg.cropping(to: CGRect(x: side == 0 ? 0 : cg.width / 2,
                    y: 0, width: side == 0 ? cg.width / 2 : cg.width - cg.width / 2,
                    height: cg.height)) else { return nil }
            image = UIImage(cgImage: crop, scale: frame.image.scale, orientation: .up)
        } else {
            // With an edge spine, the second view controller is the back.
            // A next-page image on the reverse must not advance two viewports.
            let isBack = frames.rightToLeft ? side == 0 : side == 1
            image = isBack ? (frames.frame(at: offset + 1)?.image ?? frame.image) : frame.image
        }
        let face = ReaderPageFaceController(index: index, image: image, background: background)
        faces[index] = face
        return face
    }

    private func pair(at offset: Int) -> [UIViewController] {
        let start = offset * directionSign * 2
        let pair = [face(at: start), face(at: start + 1)].compactMap { $0 }
        // UIKit's edge-spine presentation accepts one visible controller;
        // dataSource supplies the adjacent reverse face for double-sided curl.
        if !isSpread { return frames.rightToLeft ? Array(pair.suffix(1)) : Array(pair.prefix(1)) }
        return pair
    }

    func canTurn(forward: Bool) -> Bool {
        !invalidated && !isTurning && (forward ? frames.next != nil : frames.previous != nil)
    }

    @discardableResult
    func turn(forward: Bool) -> Bool {
        guard canTurn(forward: forward), let target = frames.frame(at: forward ? 1 : -1) else { return false }
        begin()
        let direction: UIPageViewController.NavigationDirection = forward != frames.rightToLeft ? .forward : .reverse
        let offset = forward ? 1 : -1
        let transitionControllers: [UIViewController]
        if isSpread {
            transitionControllers = pair(at: offset)
        } else {
            // Unlike initial/nonanimated setup, an animated edge-spine turn
            // requires the destination FRONT and the preceding sheet's BACK.
            let frontIndex = offset * directionSign * 2 + (frames.rightToLeft ? 1 : 0)
            let backIndex = frontIndex + (direction == .forward ? -1 : 1)
            transitionControllers = [face(at: frontIndex), face(at: backIndex)].compactMap { $0 }
        }
        pageController.setViewControllers(transitionControllers, direction: direction, animated: true) { [weak self] finished in
            guard let self, !self.invalidated else { return }
            if finished { self.onCommit?(target) }
            else { self.cancel() }
        }
        return true
    }

    private func revealForTouch() {
        guard !invalidated else { return }
        showImages(true)
        // A stationary edge touch may never become a UIKit page gesture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.isTurning else { return }
            self.showImages(false)
        }
    }

    private func showImages(_ visible: Bool) {
        for face in faces.values { face.setPaperVisible(visible) }
    }

    private func begin() {
        guard !isTurning else { return }
        isTurning = true
        showImages(true)
        onBegin?()
    }

    func cancel() {
        guard !invalidated else { return }
        installSource()
        isTurning = false
        showImages(false)
        onCancel?()
    }

    /// Called before close, resize, settings, memory pressure or a new epoch.
    func invalidate() {
        invalidated = true
        onCommit = nil
        onBegin = nil
        onCancel = nil
        pageController.dataSource = nil
        pageController.delegate = nil
        pageController.gestureRecognizers.forEach { $0.isEnabled = false }
        view.isUserInteractionEnabled = false
        isTurning = false
        faces.removeAll()
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard !invalidated, let face = viewController as? ReaderPageFaceController else { return nil }
        let result = self.face(at: face.index - 1)
        result?.setPaperVisible(true)
        return result
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard !invalidated, let face = viewController as? ReaderPageFaceController else { return nil }
        let result = self.face(at: face.index + 1)
        result?.setPaperVisible(true)
        return result
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) { begin() }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard !invalidated else { return }
        let indices = pageViewController.viewControllers?.compactMap { ($0 as? ReaderPageFaceController)?.index } ?? []
        guard completed, let first = isSpread ? indices.min() : indices.first
        else { cancel(); return }
        let offset = Int(floor(Double(first) / 2)) * directionSign
        guard offset != 0, let target = frames.frame(at: offset) else { cancel(); return }
        onCommit?(target)
    }
}

private final class ReaderPageFaceController: UIViewController {
    let index: Int
    private let image: UIImage
    private let background: UIColor
    private let imageView = UIImageView()

    init(index: Int, image: UIImage, background: UIColor) {
        self.index = index
        self.image = image
        self.background = background
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isOpaque = false
        imageView.image = image
        imageView.contentMode = .scaleToFill
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
    }
    func setPaperVisible(_ visible: Bool) {
        loadViewIfNeeded()
        imageView.isHidden = !visible
        view.backgroundColor = visible ? background : .clear
    }
}

/// Only a page edge starts a curl. Body links, text selection and long-press
/// remain on the real WKWebView; during a turn the overlay owns the viewport.
private final class ReaderTurnTouchView: UIView {
    var isBusy: (() -> Bool)?
    var canStart: ((CGPoint) -> Bool)?
    var willReceiveTouch: (() -> Void)?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point), !isHidden, alpha > 0 else { return nil }
        guard isBusy?() == true || canStart?(point) == true else { return nil }
        if event?.type == .touches { willReceiveTouch?() }
        return super.hitTest(point, with: event)
    }
}
