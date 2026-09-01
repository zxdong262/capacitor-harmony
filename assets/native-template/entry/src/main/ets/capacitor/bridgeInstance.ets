import { CapacitorBridge } from './CapacitorBridge';

/**
 * Holds the single `CapacitorBridge` for the current ability so that lifecycle
 * callbacks in `EntryAbility` can reach it without coupling the two files
 * through a circular import.
 */
export class BridgeHolder {
  static bridge: CapacitorBridge | null = null;
}
