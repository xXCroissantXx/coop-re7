// CoopNet.cs: RE7 co-op transport (REFramework C# source plugin).
//
// Moves player-state samples between two game instances over UDP. It touches no
// game API: the Lua side (coop_dummy.lua) writes the local player's state to
// reframework/data/coopnet_out.txt and reads the peer's samples from
// reframework/data/coopnet_in.txt. That file bridge is a stopgap until the
// ghost is driven from C# directly.
//
// Modes (reframework/data/coopnet_config.json):
//   "echo":  send to our own socket on 127.0.0.1, so the ghost replays us
//            through the full network path. One PC, no firewall prompt.
//   "udp":   send to peerHost:peerPort. Needs a reachable port.
//   "steam": send to peerSteamId over Valve's relay (ISteamNetworkingMessages,
//            P/Invoked from the game's own steam_api64.dll). No port forwarding.
//
// Packet (64 bytes, little endian):
//   "R7C2" | u32 seq | f64 senderTime | f32 px py pz | f32 qx qy qz qw
//   | u32 animBank | u32 animId | f32 animFrame | f32 lookYaw lookPitch

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using REFrameworkNET;
using REFrameworkNET.Attributes;

public class CoopNet
{
    class Config
    {
        public string mode { get; set; } = "echo";
        public string bindHost { get; set; } = "127.0.0.1";
        public int localPort { get; set; } = 27777;
        public string peerHost { get; set; } = "127.0.0.1";
        public int peerPort { get; set; } = 27777;
        public int sendHz { get; set; } = 30;
        public string peerSteamId { get; set; } = "";   // friend's SteamID64, "steam" mode
        public int steamChannel { get; set; } = 7;
        // "bot" mode: a fake remote player walking a circle around where we stand,
        // delivered through the normal receive path with simulated network trouble.
        public double botRadius { get; set; } = 3.0;
        public double botSpeed { get; set; } = 1.3;      // m/s
        public double botPauseEvery { get; set; } = 8.0; // s of walking, then a pause
        public double botPauseFor { get; set; } = 2.5;   // s standing still
        public double botYawOffsetDeg { get; set; } = 0.0;
        // Cycle the bot's facing every botDirEvery s: forward, 90, 180, 270 degrees
        // off its direction of travel, to exercise strafe and backpedal clips.
        public bool botDirCycle { get; set; } = true;
        public double botDirEvery { get; set; } = 4.0;
        // Cycle stance every botStanceEvery s (walk, jog, crouch), sending the same
        // stance flags a real player's PlayerMovement produces.
        public bool botStanceCycle { get; set; } = true;
        public double botStanceEvery { get; set; } = 16.0;
        public double botTurnRateDeg { get; set; } = 240;   // facing changes turn, not snap
        public double botJogSpeed { get; set; } = 3.4;
        public double botCrouchSpeed { get; set; } = 0.9;
        public double simLatencyMs { get; set; } = 80;
        public double simJitterMs { get; set; } = 30;
        public double simLossPct { get; set; } = 5;
    }

    // Fake remote player ----------------------------------------------------------

    static class Bot
    {
        static bool s_haveCenter;
        static float s_cx, s_cy, s_cz;
        static double s_angle, s_walked, s_facing;
        static bool s_paused;
        static double s_pauseLeft;
        static uint s_seq;
        static readonly Stopwatch s_clock = Stopwatch.StartNew();
        static double s_last;
        static readonly Random s_rng = new Random();
        static readonly List<(double due, byte[] pkt)> s_inFlight = new List<(double, byte[])>();
        public static string Expect = "-";

        static int Stance(Config c, double now) =>
            c.botStanceCycle ? (int)(now / Math.Max(1, c.botStanceEvery)) % 3 : 0;

        static double StanceSpeed(Config c, double now) => Stance(c, now) switch
        {
            1 => c.botJogSpeed,
            2 => c.botCrouchSpeed,
            _ => c.botSpeed,
        };

        public static void SetCenter(Sample local)
        {
            if (s_haveCenter) return;
            s_cx = local.Px; s_cy = local.Py; s_cz = local.Pz;
            s_haveCenter = true;
        }

        // Advance the bot, "send" a packet into the simulated network, and deliver
        // whatever has finished its simulated trip.
        public static void Tick(Config c, Action<byte[]> deliver)
        {
            double now = s_clock.Elapsed.TotalSeconds;
            double dt = s_last == 0 ? 0 : now - s_last;
            s_last = now;
            if (!s_haveCenter) return;

            if (s_paused)
            {
                s_pauseLeft -= dt;
                if (s_pauseLeft <= 0) { s_paused = false; s_walked = 0; }
            }
            else
            {
                s_angle += StanceSpeed(c, now) * dt / Math.Max(0.5, c.botRadius);
                s_walked += dt;
                if (c.botPauseEvery > 0 && s_walked >= c.botPauseEvery) { s_paused = true; s_pauseLeft = c.botPauseFor; }
            }

            var s = new Sample { Seq = ++s_seq, T = now };
            s.Px = (float)(s_cx + c.botRadius * Math.Sin(s_angle));
            s.Py = s_cy;
            s.Pz = (float)(s_cz + c.botRadius * Math.Cos(s_angle));
            // Face along the circle (tangent), plus a configurable offset in case the
            // engine's forward axis differs.
            int phase = c.botDirCycle ? (int)(now / Math.Max(1, c.botDirEvery)) % 4 : 0;
            // Facing = travel + phase*90 deg, so travel relative to facing is -phase*90.
            // With +Z forward and right = local -X (Lua's convention), +90 means
            // moving to the bot's right.
            int stance = Stance(c, now);   // 0 walk, 1 jog, 2 crouch
            var stanceName = new[] { "walk", "jog", "crouch" }[stance];
            Expect = s_paused ? (stance == 2 ? "crouch, standing" : "standing")
                              : stanceName + " " + new[] { "fwd", "right", "back", "left" }[phase];
            // Turn toward the phase's facing offset at botTurnRateDeg, shortest way round.
            double target = phase * Math.PI / 2;
            double diff = Math.IEEERemainder(target - s_facing, 2 * Math.PI);
            double step = c.botTurnRateDeg * Math.PI / 180 * dt;
            s_facing += Math.Abs(diff) <= step ? diff : Math.Sign(diff) * step;
            double yaw = s_angle + Math.PI / 2 + s_facing + c.botYawOffsetDeg * Math.PI / 180;
            s.Qx = 0; s.Qy = (float)Math.Sin(yaw / 2); s.Qz = 0; s.Qw = (float)Math.Cos(yaw / 2);
            // Same flags as Lua's local_stance_flags: bit0 crouch, bit1 walking, bit2 valid.
            s.Bank = 4u | (stance == 2 ? 1u : 0u) | (stance == 0 ? 2u : 0u);
            // Look around like a player: slow sweep left/right, gentle up/down.
            s.LookYaw = (float)(0.9 * Math.Sin(now * 0.7));
            s.LookPitch = (float)(0.35 * Math.Sin(now * 0.45));

            if (s_rng.NextDouble() * 100 >= c.simLossPct)
            {
                double delay = (c.simLatencyMs + (s_rng.NextDouble() * 2 - 1) * c.simJitterMs) / 1000.0;
                s_inFlight.Add((now + Math.Max(0, delay), Encode(s)));
            }
            for (int i = s_inFlight.Count - 1; i >= 0; i--)
            {
                if (s_inFlight[i].due <= now) { deliver(s_inFlight[i].pkt); s_inFlight.RemoveAt(i); }
            }
        }
    }

    // Steam transport (flat API of the game's steam_api64.dll) --------------------
    // The game has already initialised Steam; the accessors return its interfaces.

    static class Steam
    {
        const string Dll = "steam_api64";
        const int IdentitySize = 136;        // SteamNetworkingIdentity
        const int SendUnreliableNoNagle = 1; // k_nSteamNetworkingSend_UnreliableNoNagle
        const int SendAutoRestart = 32;      // k_nSteamNetworkingSend_AutoRestartBrokenSession

        [DllImport(Dll)] static extern IntPtr SteamAPI_SteamNetworkingMessages_SteamAPI_v002();
        [DllImport(Dll)] static extern IntPtr SteamAPI_SteamNetworkingUtils_SteamAPI_v003();
        [DllImport(Dll)] static extern IntPtr SteamAPI_SteamUser_v021();
        [DllImport(Dll)] static extern IntPtr SteamAPI_SteamFriends_v017();
        [DllImport(Dll)] static extern ulong SteamAPI_ISteamUser_GetSteamID(IntPtr self);
        [DllImport(Dll)] static extern IntPtr SteamAPI_ISteamFriends_GetPersonaName(IntPtr self);
        [DllImport(Dll)] static extern void SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(IntPtr self);
        [DllImport(Dll)] static extern int SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus(IntPtr self, IntPtr details);
        [DllImport(Dll)] static extern void SteamAPI_SteamNetworkingIdentity_Clear(IntPtr self);
        [DllImport(Dll)] static extern void SteamAPI_SteamNetworkingIdentity_SetSteamID64(IntPtr self, ulong id);
        [DllImport(Dll)] static extern ulong SteamAPI_SteamNetworkingIdentity_GetSteamID64(IntPtr self);
        [DllImport(Dll)] static extern int SteamAPI_ISteamNetworkingMessages_SendMessageToUser(
            IntPtr self, IntPtr identity, byte[] data, uint size, int flags, int channel);
        [DllImport(Dll)] static extern int SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(
            IntPtr self, int channel, [Out] IntPtr[] messages, int max);
        [DllImport(Dll)] [return: MarshalAs(UnmanagedType.I1)]
        static extern bool SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(IntPtr self, IntPtr identity);
        [DllImport(Dll)] static extern void SteamAPI_SteamNetworkingMessage_t_Release(IntPtr msg);

        static IntPtr s_msgs, s_utils, s_peerIdentity;
        static int s_channel;
        static readonly IntPtr[] s_inbox = new IntPtr[32];
        public static ulong SelfId;
        public static string SelfName = "?";
        public static int LastSendResult;

        public static void Init(int channel)
        {
            s_msgs = SteamAPI_SteamNetworkingMessages_SteamAPI_v002();
            s_utils = SteamAPI_SteamNetworkingUtils_SteamAPI_v003();
            var user = SteamAPI_SteamUser_v021();
            var friends = SteamAPI_SteamFriends_v017();
            if (s_msgs == IntPtr.Zero || s_utils == IntPtr.Zero || user == IntPtr.Zero)
                throw new InvalidOperationException("Steam interfaces unavailable (is Steam running?)");
            SelfId = SteamAPI_ISteamUser_GetSteamID(user);
            if (friends != IntPtr.Zero) SelfName = Marshal.PtrToStringUTF8(SteamAPI_ISteamFriends_GetPersonaName(friends)) ?? "?";
            SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(s_utils);

            s_channel = channel;
            s_peerIdentity = Marshal.AllocHGlobal(IdentitySize);
            SteamAPI_SteamNetworkingIdentity_Clear(s_peerIdentity);
        }

        public static void SetPeer(ulong peer)
        {
            SteamAPI_SteamNetworkingIdentity_Clear(s_peerIdentity);
            if (peer == 0) return;
            SteamAPI_SteamNetworkingIdentity_SetSteamID64(s_peerIdentity, peer);
            SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(s_msgs, s_peerIdentity);
        }

        // ESteamNetworkingAvailability: 100 = Current, 3 = Attempting, <0 = failed
        public static int RelayStatus() =>
            s_utils == IntPtr.Zero ? 0 : SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus(s_utils, IntPtr.Zero);

        public static void Send(byte[] pkt)
        {
            LastSendResult = SteamAPI_ISteamNetworkingMessages_SendMessageToUser(
                s_msgs, s_peerIdentity, pkt, (uint)pkt.Length, SendUnreliableNoNagle | SendAutoRestart, s_channel);
        }

        // Non-blocking: drains whatever arrived since the last call.
        public static void Poll(Action<byte[], ulong> onPacket)
        {
            int n = SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(s_msgs, s_channel, s_inbox, s_inbox.Length);
            for (int i = 0; i < n; i++)
            {
                var m = s_inbox[i];
                // SteamNetworkingMessage_t: void* m_pData @0, int m_cbSize @8, identity @16
                var data = Marshal.ReadIntPtr(m, 0);
                var size = Marshal.ReadInt32(m, 8);
                var from = SteamAPI_SteamNetworkingIdentity_GetSteamID64(m + 16);
                var buf = new byte[Math.Max(0, size)];
                if (size > 0) Marshal.Copy(data, buf, 0, size);
                SteamAPI_SteamNetworkingMessage_t_Release(m);
                onPacket(buf, from);
            }
        }

        public static void Shutdown()
        {
            if (s_peerIdentity != IntPtr.Zero) { Marshal.FreeHGlobal(s_peerIdentity); s_peerIdentity = IntPtr.Zero; }
        }
    }

    struct Sample
    {
        public uint Seq;
        public double T;
        public float Px, Py, Pz, Qx, Qy, Qz, Qw;
        public uint Bank, Id;
        public float Frame;
        public float LookYaw, LookPitch;   // camera relative to body, radians
    }

    const int PacketSize = 64;
    static readonly byte[] Magic = { (byte)'R', (byte)'7', (byte)'C', (byte)'2' };
    const int KeepSamples = 32;

    static string s_dataDir;
    static Config s_cfg;
    static UdpClient s_sock;
    static IPEndPoint s_peer;
    static Thread s_recvThread, s_ioThread;
    static volatile bool s_running;

    static readonly object s_lock = new object();
    static readonly LinkedList<Sample> s_received = new LinkedList<Sample>();
    static bool s_inDirty;
    static long s_sent, s_recv, s_bad;
    static string s_lastFrom = "-";
    static uint s_lastSentSeq;

    [PluginEntryPoint]
    public static void Main()
    {
        try
        {
            var exe = Process.GetCurrentProcess().MainModule.FileName;
            s_dataDir = Path.Combine(Path.GetDirectoryName(exe), "reframework", "data");
            Directory.CreateDirectory(s_dataDir);
            s_cfg = LoadConfig();
            s_running = true;

            // Steam starts in every mode so the in-game Connect panel can show our own
            // SteamID and switch to a friend live, even from bot mode.
            try { Steam.Init(s_cfg.steamChannel); s_steamReady = true; }
            catch (Exception e) { API.LogWarning("[CoopNet] Steam unavailable: " + e.Message); }

            if (IsSteam)
            {
                if (!s_steamReady) throw new InvalidOperationException("steam mode but Steam is unavailable");
                var want = (s_cfg.peerSteamId ?? "").Trim();
                s_peerSteam = want == "self" ? Steam.SelfId          // loopback experiment
                    : ulong.TryParse(want, NumberStyles.None, Inv, out var id) ? id : 0;  // 0: just show our own id
                Steam.SetPeer(s_peerSteam);
                API.LogInfo($"[CoopNet] steam self={Steam.SelfId} ({Steam.SelfName}) peer={s_peerSteam}");
            }
            else if (s_cfg.mode == "bot")
            {
                API.LogInfo("[CoopNet] bot mode: fake peer around the local player");
            }
            else
            {
                var bind = new IPEndPoint(IPAddress.Parse(s_cfg.bindHost), s_cfg.localPort);
                s_sock = new UdpClient(bind);
                s_peer = s_cfg.mode == "echo"
                    ? new IPEndPoint(IPAddress.Loopback, s_cfg.localPort)
                    : new IPEndPoint(Dns.GetHostAddresses(s_cfg.peerHost)[0], s_cfg.peerPort);
                s_recvThread = new Thread(RecvLoop) { IsBackground = true, Name = "CoopNet.Recv" };
                s_recvThread.Start();
            }

            s_ioThread = new Thread(IoLoop) { IsBackground = true, Name = "CoopNet.IO" };
            s_ioThread.Start();
            API.LogInfo($"[CoopNet] started mode={s_cfg.mode} peer={PeerText} sendHz={s_cfg.sendHz}");
            WriteStatus("started");
        }
        catch (Exception e)
        {
            API.LogError("[CoopNet] start failed: " + e);
            WriteStatusSafe("start failed: " + e.Message);
        }
    }

    [PluginExitPoint]
    public static void OnUnload()
    {
        s_running = false;
        try { s_sock?.Close(); } catch { }
        s_recvThread?.Join(1000);
        s_ioThread?.Join(1000);
        if (IsSteam) Steam.Shutdown();
        API.LogInfo("[CoopNet] stopped");
    }

    static ulong s_peerSteam;
    static bool s_steamReady;
    static string s_lastCommand = "-";

    // In-game Connect panel: Lua writes one line to coopnet_command.txt
    // ("steam <SteamID64>" or "bot"); applied here live and saved to the config.
    static void PollCommand()
    {
        var path = Path.Combine(s_dataDir, "coopnet_command.txt");
        if (!File.Exists(path)) return;
        string cmd;
        try { cmd = File.ReadAllText(path).Trim(); File.Delete(path); }
        catch (IOException) { return; }
        var parts = cmd.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 2 && parts[0] == "steam" && s_steamReady &&
            ulong.TryParse(parts[1], NumberStyles.None, Inv, out var id) && id > 76561197960265728UL)
        {
            s_cfg.mode = "steam";
            s_cfg.peerSteamId = parts[1];
            s_peerSteam = id;
            Steam.SetPeer(id);
            s_lastCommand = "connected to " + parts[1];
        }
        else if (parts.Length == 1 && parts[0] == "bot")
        {
            s_cfg.mode = "bot";
            s_lastCommand = "bot test";
        }
        else
        {
            s_lastCommand = "rejected: " + cmd;
            WriteStatus("running");
            return;
        }
        lock (s_lock) { s_received.Clear(); s_inDirty = true; }   // drop the old peer's samples
        SaveConfig();
        API.LogInfo("[CoopNet] command: " + s_lastCommand);
        WriteStatus("running");
    }

    static void SaveConfig()
    {
        var path = Path.Combine(s_dataDir, "coopnet_config.json");
        File.WriteAllText(path, JsonSerializer.Serialize(s_cfg, new JsonSerializerOptions { WriteIndented = true }));
    }
    static bool IsSteam => s_cfg != null && s_cfg.mode == "steam";
    static string PeerText => IsSteam ? $"steam:{s_peerSteam}" : s_peer?.ToString() ?? "-";

    static void OnPacket(byte[] data, string from)
    {
        if (!TryDecode(data, out var s)) { Interlocked.Increment(ref s_bad); return; }
        lock (s_lock)
        {
            s_received.AddLast(s);
            while (s_received.Count > KeepSamples) s_received.RemoveFirst();
            s_inDirty = true;
            s_recv++;
            s_lastFrom = from;
        }
    }

    static Config LoadConfig()
    {
        var path = Path.Combine(s_dataDir, "coopnet_config.json");
        if (!File.Exists(path))
        {
            var def = new Config();
            File.WriteAllText(path, JsonSerializer.Serialize(def, new JsonSerializerOptions { WriteIndented = true }));
            return def;
        }
        return JsonSerializer.Deserialize<Config>(File.ReadAllText(path)) ?? new Config();
    }

    // Receive thread ----------------------------------------------------------

    static void RecvLoop()
    {
        var from = new IPEndPoint(IPAddress.Any, 0);
        while (s_running)
        {
            byte[] data;
            try { data = s_sock.Receive(ref from); }
            catch (SocketException) { if (!s_running) return; continue; }
            catch (ObjectDisposedException) { return; }

            OnPacket(data, from.ToString());
        }
    }

    // IO thread: Lua out-file -> socket, received samples -> Lua in-file ---------

    static void IoLoop()
    {
        var outPath = Path.Combine(s_dataDir, "coopnet_out.txt");
        var inPath = Path.Combine(s_dataDir, "coopnet_in.txt");
        var period = TimeSpan.FromMilliseconds(1000.0 / Math.Max(1, s_cfg.sendHz));
        var lastStatus = Stopwatch.StartNew();

        while (s_running)
        {
            var started = Stopwatch.StartNew();
            try
            {
                if (TryReadOut(outPath, out var s) && s.Seq != s_lastSentSeq)
                {
                    s_lastSentSeq = s.Seq;
                    var pkt = Encode(s);
                    if (IsSteam)
                    {
                        if (s_peerSteam != 0) { Steam.Send(pkt); s_sent++; }
                    }
                    else if (s_cfg.mode == "bot")
                    {
                        Bot.SetCenter(s);   // the bot circles where we first stood
                    }
                    else
                    {
                        s_sock.Send(pkt, pkt.Length, s_peer);
                        s_sent++;
                    }
                }
                PollCommand();
                if (IsSteam) Steam.Poll((data, from) => OnPacket(data, "steam:" + from));
                if (s_cfg.mode == "bot") { Bot.Tick(s_cfg, pkt => OnPacket(pkt, "bot")); s_sent++; }
                WriteInFileIfDirty(inPath);
                if (lastStatus.ElapsedMilliseconds > 1000)
                {
                    lastStatus.Restart();
                    WriteStatus("running");
                }
            }
            catch (ObjectDisposedException) { return; }
            catch (Exception e) { WriteStatusSafe("io error: " + e.Message); }

            var left = period - started.Elapsed;
            if (left > TimeSpan.Zero) Thread.Sleep(left);
        }
    }

    static bool TryReadOut(string path, out Sample s)
    {
        s = default;
        string line;
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var sr = new StreamReader(fs);
            line = sr.ReadLine();
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        return line != null && TryParseLine(line, out s);
    }

    static void WriteInFileIfDirty(string path)
    {
        string text;
        lock (s_lock)
        {
            if (!s_inDirty) return;
            s_inDirty = false;
            var sb = new StringBuilder();
            foreach (var s in s_received) sb.AppendLine(FormatLine(s));
            text = sb.ToString();
        }
        // Replace atomically so Lua never reads a half-written file.
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text);
        File.Move(tmp, path, true);
    }

    static void WriteStatus(string state)
    {
        string text;
        lock (s_lock)
        {
            text = $"state={state}\nmode={s_cfg.mode}\npeer={PeerText}\nsent={s_sent}\nrecv={s_recv}\nbad={s_bad}\nlastFrom={s_lastFrom}\n" +
                   $"time={DateTime.Now:HH:mm:ss}\n";
            if (s_cfg.mode == "bot") text += $"botExpect={Bot.Expect}\n";
            if (s_steamReady)
                text += $"steamSelf={Steam.SelfId}\nsteamName={Steam.SelfName}\nrelayStatus={Steam.RelayStatus()}\n";
            if (IsSteam) text += $"lastSendResult={Steam.LastSendResult}\n";
            text += $"lastCommand={s_lastCommand}\n";
        }
        WriteStatusSafe(text);
    }

    static void WriteStatusSafe(string text)
    {
        try { if (s_dataDir != null) File.WriteAllText(Path.Combine(s_dataDir, "coopnet_status.txt"), text); } catch { }
    }

    // Text line <-> sample: "seq t px py pz qx qy qz qw bank id frame" ----------

    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    static bool TryParseLine(string line, out Sample s)
    {
        s = default;
        var p = line.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (p.Length < 14) return false;
        try
        {
            s.Seq = uint.Parse(p[0], Inv);
            s.T = double.Parse(p[1], Inv);
            s.Px = float.Parse(p[2], Inv); s.Py = float.Parse(p[3], Inv); s.Pz = float.Parse(p[4], Inv);
            s.Qx = float.Parse(p[5], Inv); s.Qy = float.Parse(p[6], Inv); s.Qz = float.Parse(p[7], Inv); s.Qw = float.Parse(p[8], Inv);
            s.Bank = uint.Parse(p[9], Inv); s.Id = uint.Parse(p[10], Inv);
            s.Frame = float.Parse(p[11], Inv);
            s.LookYaw = float.Parse(p[12], Inv); s.LookPitch = float.Parse(p[13], Inv);
            return true;
        }
        catch (FormatException) { return false; }
        catch (OverflowException) { return false; }
    }

    static string FormatLine(Sample s) => string.Format(Inv,
        "{0} {1:R} {2:R} {3:R} {4:R} {5:R} {6:R} {7:R} {8:R} {9} {10} {11:R} {12:R} {13:R}",
        s.Seq, s.T, s.Px, s.Py, s.Pz, s.Qx, s.Qy, s.Qz, s.Qw, s.Bank, s.Id, s.Frame, s.LookYaw, s.LookPitch);

    // Binary packet <-> sample ----------------------------------------------------

    static byte[] Encode(Sample s)
    {
        var b = new byte[PacketSize];
        var w = new BinaryWriter(new MemoryStream(b));
        w.Write(Magic);
        w.Write(s.Seq); w.Write(s.T);
        w.Write(s.Px); w.Write(s.Py); w.Write(s.Pz);
        w.Write(s.Qx); w.Write(s.Qy); w.Write(s.Qz); w.Write(s.Qw);
        w.Write(s.Bank); w.Write(s.Id); w.Write(s.Frame);
        w.Write(s.LookYaw); w.Write(s.LookPitch);
        return b;
    }

    static bool TryDecode(byte[] b, out Sample s)
    {
        s = default;
        if (b.Length != PacketSize || b[0] != Magic[0] || b[1] != Magic[1] || b[2] != Magic[2] || b[3] != Magic[3])
            return false;
        var r = new BinaryReader(new MemoryStream(b, 4, PacketSize - 4));
        s.Seq = r.ReadUInt32(); s.T = r.ReadDouble();
        s.Px = r.ReadSingle(); s.Py = r.ReadSingle(); s.Pz = r.ReadSingle();
        s.Qx = r.ReadSingle(); s.Qy = r.ReadSingle(); s.Qz = r.ReadSingle(); s.Qw = r.ReadSingle();
        s.Bank = r.ReadUInt32(); s.Id = r.ReadUInt32(); s.Frame = r.ReadSingle();
        s.LookYaw = r.ReadSingle(); s.LookPitch = r.ReadSingle();
        return true;
    }
}
