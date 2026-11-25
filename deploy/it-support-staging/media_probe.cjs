const assert = require("node:assert/strict");
const fs = require("node:fs");
const { chromium } = require("playwright");

async function main() {
  const file = process.argv[2];
  assert(file, "Pass the short-lived staging ICE bundle filename");
  const servers = JSON.parse(fs.readFileSync(file, "utf8"));
  assert(Array.isArray(servers) && servers.length, "No TURN credentials were supplied");
  const browser = await chromium.launch({
    headless: false,
    args: ["--auto-select-desktop-capture-source=Entire screen"]
  });
  try {
    for (const server of servers) {
      assert(typeof server.urls === "string" && /^turns?:/.test(server.urls), "Use a single TURN URL per probe");
      const page = await browser.newPage({ viewport: { width: 900, height: 650 } });
      try {
        await page.goto("http://127.0.0.1:19084");
        await page.getByRole("button", { name: "Share desktop" }).click();
        await page.waitForFunction(() => window.desktopCapture, { }, { timeout: 15000 });
        const result = await page.evaluate(async (iceServer) => {
          const stream = await window.desktopCapture;
          const track = stream.getVideoTracks()[0];
          if (track.getSettings().displaySurface !== "monitor") throw new Error("Expected native monitor capture");
          const config = { iceServers: [iceServer], iceTransportPolicy: "relay" };
          const sender = new RTCPeerConnection(config);
          const receiver = new RTCPeerConnection(config);
          let timer;
          const transfer = async () => {
            sender.addTrack(track, stream);
            const video = document.createElement("video");
            video.muted = true;
            video.autoplay = true;
            document.body.appendChild(video);
            receiver.ontrack = event => { video.srcObject = event.streams[0]; };
            async function describe(peer, description) {
              await peer.setLocalDescription(description);
              if (peer.iceGatheringState !== "complete") {
                await new Promise(resolve => {
                  const complete = () => {
                    if (peer.iceGatheringState !== "complete") return;
                    peer.removeEventListener("icegatheringstatechange", complete);
                    resolve();
                  };
                  peer.addEventListener("icegatheringstatechange", complete);
                  complete();
                });
              }
              return peer.localDescription;
            }

            await receiver.setRemoteDescription(await describe(sender, await sender.createOffer()));
            await sender.setRemoteDescription(await describe(receiver, await receiver.createAnswer()));
            await new Promise(resolve => video.requestVideoFrameCallback(resolve));
            const stats = await receiver.getStats();
            const transport = [...stats.values()].find(report => report.type === "transport" && report.selectedCandidatePairId);
            const pair = stats.get(transport?.selectedCandidatePairId);
            const local = stats.get(pair?.localCandidateId);
            const remote = stats.get(pair?.remoteCandidateId);
            return {
              capture: track.getSettings().displaySurface,
              width: video.videoWidth,
              height: video.videoHeight,
              localCandidate: local?.candidateType,
              remoteCandidate: remote?.candidateType,
              relayProtocol: local?.relayProtocol
            };
          };
          try {
            return await Promise.race([transfer(), new Promise((_, reject) => {
              timer = setTimeout(() => reject(new Error("Relay media did not render within 30 seconds")), 30000);
            })]);
          } finally {
            clearTimeout(timer);
            sender.close();
            receiver.close();
            stream.getTracks().forEach(t => t.stop());
          }
        }, server);
        assert.equal(result.capture, "monitor");
        assert(result.width > 0 && result.height > 0, "No decoded frame");
        assert.equal(result.localCandidate, "relay");
        assert.equal(result.remoteCandidate, "relay");
        if (server.urls.startsWith("turns:")) assert.equal(result.relayProtocol, "tls");
        if (server.urls.endsWith("transport=udp")) assert.equal(result.relayProtocol, "udp");
        // Omit ICE credentials, raw SDP and candidate addresses.
        console.log(JSON.stringify({ scenario: "desktop_capture_relay_playback", ...result }));
      } finally {
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
}
main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
