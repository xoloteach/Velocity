/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export default function App() {
  return (
    <main className="fixed inset-0 w-screen h-screen overflow-hidden bg-[#0a111a]">
      <iframe
        title="Project Velocity"
        src="/game/index.html"
        className="block w-full h-full border-0 bg-[#0a111a]"
        allow="autoplay; fullscreen; gamepad; pointer-lock"
        allowFullScreen
      />
    </main>
  );
}
