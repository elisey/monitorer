/// A picture format and input that belong together: the format is chosen for what the
/// device on that input outputs.
public struct Scene: Equatable, Sendable {
    public let format: PictureFormat
    public let input: InputSource

    /// This Mac over USB-C, using the whole 21:9 panel.
    public static let usbCWide = Scene(format: .wideScreen, input: .usbC)
    /// A 16:9 device on HDMI, shown without stretching.
    public static let hdmiSixteenByNine = Scene(format: .sixteenByNine, input: .hdmi1)
}

public struct SceneController {
    private let formats: PictureFormatController
    private let inputs: InputSourceController

    public init(client: DDCClient) {
        formats = PictureFormatController(client: client)
        inputs = InputSourceController(client: client)
    }

    /// Applies the format first, then the input, so the device being switched to never
    /// sees the old format. Either step is skipped when the monitor is already there.
    public func apply(_ scene: Scene) throws(DDCError) {
        try formats.set(scene.format)
        try inputs.set(scene.input)
    }

    /// Switches to the HDMI scene when the monitor shows this Mac (or any other input),
    /// and back to the USB-C scene when it shows HDMI.
    @discardableResult
    public func toggle() throws(DDCError) -> Scene {
        let target: Scene = try inputs.current() == .hdmi1 ? .usbCWide : .hdmiSixteenByNine
        try apply(target)
        return target
    }
}
