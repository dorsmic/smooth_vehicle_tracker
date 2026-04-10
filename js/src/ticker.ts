import type { LatLng } from "./types.js";
import type { VehicleTrackingState } from "./models.js";
import { VehicleTrackingEngine } from "./engine.js";

export type VehicleTrackingTickCallback = (
  state: VehicleTrackingState,
  now: Date,
) => void;

/**
 * Lightweight orchestrator for `engine.tick()` on a fixed interval.
 * Mirrors the Dart-side VehicleTrackingTicker concept.
 */
export class VehicleTrackingTicker {
  readonly engine: VehicleTrackingEngine;
  readonly intervalMs: number;

  private _timer: ReturnType<typeof setInterval> | null = null;
  private _onTick: VehicleTrackingTickCallback | null = null;
  private _polylineProvider: (() => LatLng[] | null | undefined) | null = null;

  constructor(options: {
    engine: VehicleTrackingEngine;
    intervalMs?: number;
  }) {
    this.engine = options.engine;
    this.intervalMs = options.intervalMs ?? this.engine.config.tickIntervalMs;
  }

  get isRunning(): boolean {
    return this._timer !== null;
  }

  get state(): VehicleTrackingState {
    return this.engine.state;
  }

  onSsePosition(
    newPos: LatLng,
    options?: { now?: Date; polyline?: LatLng[] | null },
  ): void {
    this.engine.onSsePosition(newPos, options);
  }

  start(options?: {
    onTick?: VehicleTrackingTickCallback;
    polylineProvider?: () => LatLng[] | null | undefined;
  }): void {
    if (options?.onTick) this._onTick = options.onTick;
    if (options?.polylineProvider) this._polylineProvider = options.polylineProvider;

    this.stop();
    this._timer = setInterval(() => {
      const now = new Date();
      const tracked = this.engine.tick({
        now,
        polyline: this._polylineProvider?.() ?? undefined,
      });
      this._onTick?.(tracked, now);
    }, this.intervalMs);
  }

  stop(): void {
    if (this._timer !== null) {
      clearInterval(this._timer);
      this._timer = null;
    }
  }

  dispose(): void {
    this.stop();
    this._onTick = null;
    this._polylineProvider = null;
  }
}

