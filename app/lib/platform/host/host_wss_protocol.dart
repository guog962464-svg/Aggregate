/// Shared protocol identifiers used by the Mac Host and Android client.
/// Host WSS data messages are single, uncompressed frames bounded by this size.
const hostWssSubprotocol = 'aggregate-host.v1';
const hostWssMaxFrameBytes = 1024 * 1024;
const hostWssWebSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const hostBonjourServiceType = '_aggregate-host._tcp';
const hostWssPath = '/host';
const hostWssDefaultPort = 47321;
const hostProtocolVersion = 1;
