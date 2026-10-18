import Foundation
import CoreBluetooth
import Combine
import FeelCore

/// All CoreBluetooth callbacks and public calls are on the main queue.
/// At most the newest packet is retained; reconnect never flushes stale movement.
final class BluetoothPuck: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var status = "Bluetooth starting"
    @Published private(set) var isConnected = false
    @Published private(set) var devices: [CBPeripheral] = []
    @Published private(set) var boardStatus = "No status received"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var selection=PeripheralSelection()
    private var cancelling:Set<UUID>=[]
    private var requested:CBPeripheral?
    private var command: CBCharacteristic?
    private var pending: FeelPacket?
    private var pendingAt: TimeInterval = 0
    private var responseOutstanding = false
    private var wantedScan = false
    private let serviceID=CBUUID(string:FeelBLE.service)
    override init() { super.init(); central=CBCentralManager(delegate:self,queue:.main) }
    func scan() {
        wantedScan=true; devices=[]
        guard central.state == .poweredOn else { status="Enable Bluetooth and allow access"; return }
        central.scanForPeripherals(withServices:[serviceID],options:[CBCentralManagerScanOptionAllowDuplicatesKey:false]); status="Select your FEEL puck"
    }
    func stopScanning() {
        wantedScan=false
        central.stopScan()
    }
    func connect(_ device: CBPeripheral) {
        guard !selection.accepts(device.identifier) else { return }
        disconnect(); wantedScan=false; central.stopScan()
        if cancelling.contains(device.identifier) || device.state == .disconnecting {
            requested=device; status="Waiting for previous connection to close"; return
        }
        beginConnection(device)
    }
    private func beginConnection(_ device:CBPeripheral) {
        guard central.state == .poweredOn else { status="Bluetooth unavailable"; return }
        peripheral=device; selection.select(device.identifier); device.delegate=self
        status="Connecting to \(device.name ?? "FEEL")"; central.connect(device)
    }
    func disconnect() {
        requested=nil; pending=nil; command=nil; responseOutstanding=false; isConnected=false; selection.clear(); boardStatus="No current board status"
        let previous=peripheral; peripheral=nil
        if let previous,previous.state != .disconnected {
            cancelling.insert(previous.identifier); central.cancelPeripheralConnection(previous)
        }
    }
    private func finishCancellation(_ device:CBPeripheral)->Bool {
        guard cancelling.remove(device.identifier) != nil else { return false }
        if let requested,requested.identifier==device.identifier {
            self.requested=nil; beginConnection(requested)
        }
        return true
    }
    func send(_ packet: FeelPacket) {
        guard isConnected else { return }
        pending=packet.forActiveLayout; pendingAt=ProcessInfo.processInfo.systemUptime; flush()
    }
    private func flush() {
        guard let device=peripheral, let characteristic=command, let packet=pending, !responseOutstanding else { return }
        guard ProcessInfo.processInfo.systemUptime-pendingAt<=0.250 else { pending=nil; return }
        if characteristic.properties.contains(.writeWithoutResponse) {
            guard device.canSendWriteWithoutResponse else { return }
            pending=nil; device.writeValue(packet.data,for:characteristic,type:.withoutResponse)
        } else if characteristic.properties.contains(.write) {
            pending=nil; responseOutstanding=true; device.writeValue(packet.data,for:characteristic,type:.withResponse)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { status="Bluetooth ready"; if wantedScan { scan() } }
        else { disconnect(); cancelling=[]; requested=nil; status=central.state == .unauthorized ? "Bluetooth permission denied" : "Bluetooth unavailable" }
    }
    func centralManager(_ central: CBCentralManager,didDiscover peripheral: CBPeripheral,advertisementData: [String:Any],rssi RSSI: NSNumber) {
        if !devices.contains(where: { $0.identifier==peripheral.identifier }) { devices.append(peripheral) }
    }
    func centralManager(_ central: CBCentralManager,didConnect peripheral: CBPeripheral) { guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { central.cancelPeripheralConnection(peripheral); return }; peripheral.discoverServices([serviceID]) }
    func centralManager(_ central: CBCentralManager,didFailToConnect peripheral: CBPeripheral,error: Error?) { if finishCancellation(peripheral) { return }; guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { return }; disconnect(); status="Connection failed. Scan to retry." }
    func centralManager(_ central: CBCentralManager,didDisconnectPeripheral peripheral: CBPeripheral,error: Error?) { if finishCancellation(peripheral) { return }; guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { return }; disconnect(); status="Disconnected — puck will neutralize" }
    func peripheral(_ peripheral: CBPeripheral,didDiscoverServices error: Error?) {
        guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { return }
        guard error==nil,let service=peripheral.services?.first(where:{$0.uuid==serviceID}) else { disconnect(); status="FEEL service missing"; return }
        peripheral.discoverCharacteristics([CBUUID(string:FeelBLE.command),CBUUID(string:FeelBLE.status)],for:service)
    }
    func peripheral(_ peripheral: CBPeripheral,didDiscoverCharacteristicsFor service: CBService,error: Error?) {
        guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { return }
        guard error==nil,let found=service.characteristics?.first(where:{$0.uuid==CBUUID(string:FeelBLE.command)}),found.properties.contains(.writeWithoutResponse) || found.properties.contains(.write) else { disconnect(); status="Command characteristic unavailable"; return }
        command=found; pending=nil; isConnected=true; status="Connected: \(peripheral.name ?? "FEEL")"
        if let statusChar=service.characteristics?.first(where:{$0.uuid==CBUUID(string:FeelBLE.status)}) {
            if statusChar.properties.contains(.notify) { peripheral.setNotifyValue(true,for:statusChar) }
            if statusChar.properties.contains(.read) { peripheral.readValue(for:statusChar) }
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { return }; flush() }
    func peripheral(_ peripheral: CBPeripheral,didWriteValueFor characteristic: CBCharacteristic,error: Error?) {
        guard selection.accepts(peripheral.identifier),peripheral === self.peripheral,characteristic === command else { return }
        responseOutstanding=false
        if let error { pending=nil; status="Write error: \(error.localizedDescription)" } else { flush() }
    }
    func peripheral(_ peripheral: CBPeripheral,didUpdateValueFor characteristic: CBCharacteristic,error: Error?) {
        guard selection.accepts(peripheral.identifier),peripheral === self.peripheral else { return }
        guard error==nil,let value=characteristic.value else { return }
        do { boardStatus=try PuckStatus(bytes:Array(value)).summary }
        catch { boardStatus="Unknown board status: " + value.map { String(format:"%02x",$0) }.joined() }
    }
}
