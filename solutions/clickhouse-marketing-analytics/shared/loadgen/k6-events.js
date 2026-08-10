// Load test: simulate the mobile fleet against POST /events.
//
//   k6 run loadtest/k6-events.js                          # steady state (~1k events/s)
//   k6 run -e SCENARIO=burst loadtest/k6-events.js        # push-campaign blast (~10-20x)
//   k6 run -e BASE_URL=http://vm:8080 loadtest/k6-events.js
//
// Model (buffered REST tier): 100k concurrent users != 100k inserts/s. At typical
// mobile instrumentation (~1 event per 20-100s of active use) 100k users are
// ~1-5k events/s steady; a full-base push (the MoEngage case) spikes 10-20x.
// Each VU is one device: it batches 1-5 events per request (SDKs buffer), then
// idles. 429 responses are honored with Retry-After backoff - that is the
// client contract, not a failure.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const URLS = (__ENV.BASE_URL || 'http://localhost:8080').split(','); // comma-separated = spread VUs across instances

const eventsAccepted = new Counter('events_accepted');
const eventsRejected = new Counter('events_rejected');

const scenarios = {
  // Saturation probe: a controlled firehose, RATE requests/s x BATCH events
  // each (defaults: 100 x 200 = 20k events/s). Unlike the device scenarios,
  // this models upstream services shipping pre-batched events - use it to
  // find where the XADD -> flusher pipeline tops out. Tune with
  //   k6 run -e SCENARIO=firehose -e RATE=500 -e BATCH=200 ...   (=100k/s)
  firehose: {
    firehose: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 100),
      timeUnit: '1s',
      duration: __ENV.DURATION || '60s',
      preAllocatedVUs: Number(__ENV.VUS || 200),
      maxVUs: Number(__ENV.MAXVUS || 2000),
    },
  },
  // 30s harness check: verifies the bench tooling end to end, not a benchmark.
  smoke: {
    smoke: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 50 },
        { duration: '15s', target: 50 },
        { duration: '5s', target: 0 },
      ],
    },
  },
  steady: {
    // ~2000 devices, one 1-5 event batch every 2-6s => ~1-2.5k events/s.
    steady: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 2000 },
        { duration: '3m', target: 2000 },
        { duration: '30s', target: 0 },
      ],
    },
  },
  burst: {
    // Push-notification blast: the whole base opens the app within a minute.
    burst: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 2000 },   // steady baseline
        { duration: '1m', target: 2000 },
        { duration: '20s', target: 20000 },  // the push lands
        { duration: '1m', target: 20000 },
        { duration: '30s', target: 2000 },   // decay back
        { duration: '30s', target: 0 },
      ],
    },
  },
};

export const options = {
  scenarios: scenarios[__ENV.SCENARIO || 'steady'],
  thresholds: {
    // p99 well under the 1s flush interval: the API must never be the bottleneck.
    http_req_duration: ['p(99)<500'],
    // Steady state should see no backpressure; bursts may (that's the demo point),
    // so only hard-fail on server errors.
    'http_req_failed{expected_response:true}': ['rate<0.01'],
  },
};

const CHANNELS = ['paid_search', 'organic', 'email', 'social', 'direct'];
const EVENT_TYPES = ['page_view', 'page_view', 'page_view', 'click', 'click', 'lead', 'purchase'];
const DEVICES = ['mobile', 'mobile', 'mobile', 'desktop', 'tablet'];

function randomEvent(userId, sessionId) {
  const eventType = EVENT_TYPES[Math.floor(Math.random() * EVENT_TYPES.length)];
  const purchase = eventType === 'purchase';
  return {
    event_time: new Date().toISOString(),
    event_type: eventType,
    user_id: `u${userId}`,
    session_id: sessionId,
    campaign_id: `cmp-${String(Math.floor(Math.random() * 200)).padStart(3, '0')}`,
    channel: CHANNELS[Math.floor(Math.random() * CHANNELS.length)],
    country: 'ID',
    device_type: DEVICES[Math.floor(Math.random() * DEVICES.length)],
    conversion_value: purchase ? Math.round(150000 * Math.exp(Math.random() * 2 - 1)) : null,
    currency: purchase ? 'IDR' : null,
    properties: JSON.stringify({ app_version: '5.4', ab_variant: Math.random() < 0.5 ? 'A' : 'B' }),
  };
}

const FIREHOSE = (__ENV.SCENARIO || 'steady') === 'firehose';
const FIREHOSE_BATCH = Number(__ENV.BATCH || 200);

export default function () {
  const userId = __VU; // one VU = one device = one user
  const sessionId = `s${__VU}-${__ITER}`;
  const batch = [];
  // Devices buffer 1-5 events; the firehose ships pre-batched uploads.
  const batchSize = FIREHOSE ? FIREHOSE_BATCH : 1 + Math.floor(Math.random() * 5);
  for (let i = 0; i < batchSize; i++) {
    batch.push(randomEvent(userId, sessionId));
  }

  const headers = { 'Content-Type': 'application/json' };
  if (__ENV.API_KEY) headers['X-API-Key'] = __ENV.API_KEY;
  const res = http.post(`${URLS[__VU % URLS.length]}/events`, JSON.stringify(batch), { headers });

  check(res, { 'accepted or backpressured': (r) => r.status === 202 || r.status === 429 });

  if (res.status === 202) {
    eventsAccepted.add(batch.length);
    if (!FIREHOSE) sleep(2 + Math.random() * 4); // device idles between event batches
  } else if (res.status === 429) {
    eventsRejected.add(batch.length);
    sleep(Number(res.headers['Retry-After'] || 1)); // honor backpressure
  } else {
    sleep(1);
  }
}
