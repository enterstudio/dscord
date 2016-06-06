module dscord.gateway.client;

import std.stdio,
       std.uni,
       std.functional,
       std.zlib,
       std.datetime,
       std.variant,
       fast.json;

import vibe.core.core,
       vibe.inet.url,
       vibe.http.websockets;

import dscord.client,
       dscord.gateway.packets,
       dscord.gateway.events,
       dscord.util.json,
       dscord.util.emitter;

const ubyte MAX_RECONNECTS = 6;

alias GatewayPacketHandler = void delegate (BasePacket);
alias GatewayEventHandler = void delegate (DispatchPacket);


class GatewayClient {
  Logger     log;
  Client     client;
  WebSocket  sock;

  string  session_id;
  uint    seq;
  uint    hb_interval;
  bool    connected;
  ubyte   reconnects;
  Task    heartbeater;

  Emitter  eventEmitter;

  private {
    DispatchPacket dispatchPacket;
  }

  this(Client client) {
    this.client = client;
    this.log = this.client.log;

    this.eventEmitter = new Emitter;
    this.eventEmitter.listen!ReadyEvent(toDelegate(&this.handleReadyEvent));
    // this.eventEmitter.listen!Resumed(toDelegate(&this.handleResumedEvent));

    // Copy emitters to client for easier API access
    client.events = this.eventEmitter;

    // Create a single DispatchPacket that can be used for all dispatches (PERF)
    this.dispatchPacket = new DispatchPacket;
  }

  void start() {
    if (this.sock && this.sock.connected) this.sock.close();

    // Start the main task
    this.sock = connectWebSocket(URL(client.api.gateway()));
    runTask(toDelegate(&this.run));
  }

  void send(Serializable p) {
    JSONObject data = p.serialize();
    this.log.tracef("gateway-send: %s", data.dumps());
    this.sock.send(data.dumps());
  }

  void handleReadyEvent(ReadyEvent r) {
    this.log.infof("Recieved READY payload, starting heartbeater");
    this.hb_interval = r.heartbeatInterval;
    this.session_id = r.sessionID;
    this.heartbeater = runTask(toDelegate(&this.heartbeat));
    this.reconnects = 0;
  }

  /*void handleResumedEvent(Resumed r) {
    this.heartbeater = runTask(toDelegate(&this.heartbeat));
  }*/

  void handleDispatchPacket(uint seq, string type, ref JSON obj) {
    // Update sequence number if it's larger than what we have
    if (seq > this.seq) {
      this.seq = seq;
    }

    switch (type) {
      case "READY":
        this.eventEmitter.emit!ReadyEvent(new ReadyEvent(this.client, obj));
        break;
      case "GUILD_CREATE":
        this.eventEmitter.emit!GuildCreateEvent(new GuildCreateEvent(
          this.client, obj));
        break;
      default:
        this.log.warningf("Unhandled dispatch event: %s", type);
        break;
    }

    /*
    this.log.tracef("gateway-packet: %s", d.event);
    switch (d.event) {
      case "READY":
        this.eventEmitter.emit!Ready(new Ready(this.client, d));
        break;
      case "RESUMED":
        this.eventEmitter.emit!Resumed(new Resumed(this.client, d));
        break;
      case "CHANNEL_CREATE":
        this.eventEmitter.emit!ChannelCreate(
            new ChannelCreate(this.client, d));
        break;
      case "CHANNEL_UPDATE":
        this.eventEmitter.emit!ChannelUpdate(
            new ChannelUpdate(this.client, d));
        break;
      case "CHANNEL_DELETE":
        this.eventEmitter.emit!ChannelDelete(
            new ChannelDelete(this.client, d));
        break;
      case "GUILD_BAN_ADD":
        this.eventEmitter.emit!GuildBanAdd(
            new GuildBanAdd(this.client, d));
        break;
      case "GUILD_BAN_REMOVE":
        this.eventEmitter.emit!GuildBanRemove(
            new GuildBanRemove(this.client, d));
        break;
      case "GUILD_CREATE":
        this.eventEmitter.emit!GuildCreate(
            new GuildCreate(this.client, d));
        break;
      case "GUILD_UPDATE":
        this.eventEmitter.emit!GuildUpdate(
            new GuildUpdate(this.client, d));
        break;
      case "GUILD_DELETE":
        this.eventEmitter.emit!GuildDelete(
            new GuildDelete(this.client, d));
        break;
      case "GUILD_EMOJIS_UPDATE":
        this.eventEmitter.emit!GuildEmojisUpdate(
            new GuildEmojisUpdate(this.client, d));
        break;
      case "GUILD_INTEGRATIONS_UPDATE":
        this.eventEmitter.emit!GuildIntegrationsUpdate(
            new GuildIntegrationsUpdate(this.client, d));
        break;
      case "GUILD_MEMBER_ADD":
        this.eventEmitter.emit!GuildMemberAdd(
            new GuildMemberAdd(this.client, d));
        break;
      case "GUILD_MEMBER_UPDATE":
        this.eventEmitter.emit!GuildMemberUpdate(
            new GuildMemberUpdate(this.client, d));
        break;
      case "GUILD_MEMBER_REMOVE":
        this.eventEmitter.emit!GuildMemberRemove(
            new GuildMemberRemove(this.client, d));
        break;
      case "GUILD_ROLE_CREATE":
        this.eventEmitter.emit!GuildRoleCreate(
            new GuildRoleCreate(this.client, d));
        break;
      case "GUILD_ROLE_UPDATE":
        this.eventEmitter.emit!GuildRoleUpdate(
            new GuildRoleUpdate(this.client, d));
        break;
      case "GUILD_ROLE_DELETE":
        this.eventEmitter.emit!GuildRoleDelete(
            new GuildRoleDelete(this.client, d));
        break;
      case "MESSAGE_CREATE":
        this.eventEmitter.emit!MessageCreate(
            new MessageCreate(this.client, d));
        break;
      case "MESSAGE_UPDATE":
        this.eventEmitter.emit!MessageUpdate(
            new MessageUpdate(this.client, d));
        break;
      case "MESSAGE_DELETE":
        this.eventEmitter.emit!MessageDelete(
            new MessageDelete(this.client, d));
        break;
      case "PRESENCE_UPDATE":
        this.eventEmitter.emit!PresenceUpdate(
            new PresenceUpdate(this.client, d));
        break;
      case "TYPING_START":
        this.eventEmitter.emit!TypingStart(
            new TypingStart(this.client, d));
        break;
      case "USER_SETTINGS_UPDATE":
        this.eventEmitter.emit!UserSettingsUpdate(
            new UserSettingsUpdate(this.client, d));
        break;
      case "USER_UPDATE":
        this.eventEmitter.emit!UserUpdate(
            new UserUpdate(this.client, d));
        break;
      case "VOICE_STATE_UPDATE":
        this.eventEmitter.emit!VoiceStateUpdate(
            new VoiceStateUpdate(this.client, d));
        break;
      case "VOICE_SERVER_UPDATE":
        this.eventEmitter.emit!VoiceServerUpdate(
            new VoiceServerUpdate(this.client, d));
        break;
      default:
        this.log.warningf("unhandled gateway event: %s", d.event);
    }

    debug {
      this.log.tracef("gateway event parse took %sms", sw.peek().to!("msecs", real));
    }
    */
  }

  void parse(string rawData) {
    auto json = parseTrustedJSON(rawData);

    uint seq;
    string type;
    OPCode op;

    foreach (key; json.byKey) {
      switch (key) {
        case "op":
          op = cast(OPCode)json.read!ushort;
          break;
        case "t":
          type = json.read!string;
          break;
        case "s":
          seq = json.read!uint;
          break;
        case "d":
          switch (op) {
            case OPCode.DISPATCH:
              this.handleDispatchPacket(seq, type, json);
              // this.dispatchPacket.deserialize(json);
              break;
            default:
              this.log.warningf("Unhandled gateway packet: %s", op);
              break;
          }
          break;
        default:
          this.log.tracef("K: %s", key);
          break;
      }
    }
  }

  void heartbeat() {
    while (this.connected) {
      this.send(new HeartbeatPacket(this.seq));
      sleep(this.hb_interval.msecs);
    }
  }

  void run() {
    string data;

    // If we already have a sequence number, attempt to resume
    if (this.session_id && this.seq) {
      this.send(new ResumePacket(this.client.token, this.session_id, this.seq));
    } else {
      // On startup, send the identify payload
      this.send(new IdentifyPacket(this.client.token));
    }

    this.log.info("Connected to Gateway");
    this.connected = true;

    while (this.sock.waitForData()) {
      if (!this.connected) break;

      try {
        ubyte[] rawdata = this.sock.receiveBinary();
        data = cast(string)uncompress(rawdata);
      } catch (Exception e) {
        data = this.sock.receiveText();
      }

      if (data == "") {
        continue;
      }

      try {
        // this.log.tracef("gateway-recv: %s", data);
        this.parse(data);
        // this.dispatch(new JSONObject(data));
      } catch (Exception e) {
        this.log.warning("failed to handle %s (%s)", e, data);
      }
    }

    this.log.critical("Gateway websocket closed");
    this.connected = false;
    this.reconnects++;

    if (this.reconnects > MAX_RECONNECTS) {
      this.log.errorf("Max Gateway WS reconnects (%s) hit, aborting...", this.reconnects);
      return;
    }

    if (this.reconnects > 1) {
      this.session_id = null;
      this.seq = 0;
      this.log.warning("Waiting 5 seconds before reconnecting...");
      sleep(5.seconds);
    }

    this.log.info("Attempting reconnection...");
    return this.start();
  }
}
