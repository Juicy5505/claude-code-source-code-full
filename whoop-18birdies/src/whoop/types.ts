/**
 * WHOOP v2 response shapes, narrowed to the fields this tool uses.
 *
 * v2 changed sleep/workout IDs from integers to UUIDs; cycle IDs stayed
 * numeric. Everything here treats IDs as opaque strings so a future ID change
 * cannot silently corrupt the join keys.
 */

export interface WhoopPage<T> {
  records: T[];
  next_token?: string | null;
}

export interface WhoopCycle {
  id: string;
  start: string;
  end: string | null;
  timezone_offset: string;
  score_state: ScoreState;
  score?: {
    strain: number;
    kilojoule: number;
    average_heart_rate: number;
    max_heart_rate: number;
  };
}

export interface WhoopRecovery {
  cycle_id: string;
  sleep_id: string;
  score_state: ScoreState;
  score?: {
    recovery_score: number;
    resting_heart_rate: number;
    hrv_rmssd_milli: number;
    spo2_percentage?: number;
    skin_temp_celsius?: number;
    user_calibrating?: boolean;
  };
}

export interface WhoopSleep {
  id: string;
  start: string;
  end: string;
  timezone_offset: string;
  nap: boolean;
  score_state: ScoreState;
  score?: {
    sleep_performance_percentage?: number;
    sleep_efficiency_percentage?: number;
    respiratory_rate?: number;
    sleep_consistency_percentage?: number;
    stage_summary?: {
      total_in_bed_time_milli: number;
      total_awake_time_milli: number;
      total_light_sleep_time_milli: number;
      total_slow_wave_sleep_time_milli: number;
      total_rem_sleep_time_milli: number;
      sleep_cycle_count: number;
      disturbance_count: number;
    };
  };
}

export interface WhoopWorkout {
  id: string;
  start: string;
  end: string;
  timezone_offset: string;
  sport_name?: string;
  sport_id?: number;
  score_state: ScoreState;
  score?: {
    strain: number;
    average_heart_rate: number;
    max_heart_rate: number;
    kilojoule: number;
    distance_meter?: number;
    zone_durations?: Record<string, number>;
  };
}

export interface WhoopProfile {
  user_id: number;
  email: string;
  first_name: string;
  last_name: string;
}

/**
 * WHOOP returns records before scoring finishes. Only `SCORED` records carry a
 * `score` object, so every consumer must gate on this rather than assuming
 * `score` is present.
 */
export type ScoreState = "SCORED" | "PENDING_SCORE" | "UNSCORABLE";

export interface WhoopSnapshot {
  fetchedAt: string;
  profile?: WhoopProfile;
  cycles: WhoopCycle[];
  recoveries: WhoopRecovery[];
  sleeps: WhoopSleep[];
  workouts: WhoopWorkout[];
}

export function emptySnapshot(): WhoopSnapshot {
  return {
    fetchedAt: new Date().toISOString(),
    cycles: [],
    recoveries: [],
    sleeps: [],
    workouts: [],
  };
}
