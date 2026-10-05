const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'lcrp_halloween';
const IMAGE_PATH = 'nui://ox_inventory/web/images/';
const MONTH = 'October';

const FALLBACK_EMOJI = {
    money: '💵',
    firework1: '🎆', firework2: '🎆', firework3: '🎆', firework4: '🎆',
    WEAPON_FLASHLIGHT: '🔦',
    WEAPON_KNIFE: '🔪',
    fishing_rod: '🎣', fishing_kit: '🧰',
    metal_detector: '📡',
    repair_kit: '🔧',
    bandage: '🩹', gauze: '🩹', firstaid: '⛑️',
};

const el = (id) => document.getElementById(id);
const app = el('app');
const panel = el('panel');
const wheelEl = el('wheel');

let state = null;
let selectedDay = null;
let serverOffset = 0;
let spinning = false;
let refreshing = false;
let ticker = null;
let rotation = 0;
let segmentAngles = [];
let audio = null;

/* ---------- Utilities ---------- */

function post(endpoint, data = {}) {
    return fetch(`https://${RESOURCE}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((res) => res.json()).catch(() => null);
}

const serverNow = () => Math.floor(Date.now() / 1000) + serverOffset;
const pad = (n) => String(n).padStart(2, '0');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function splitTime(seconds) {
    seconds = Math.max(0, seconds);
    return {
        d: Math.floor(seconds / 86400),
        h: Math.floor((seconds % 86400) / 3600),
        m: Math.floor((seconds % 3600) / 60),
        s: seconds % 60,
    };
}

function iconFor(reward, className) {
    const img = document.createElement('img');
    img.className = className;
    img.src = `${IMAGE_PATH}${reward.name}.png`;
    img.alt = '';
    img.onerror = () => {
        const span = document.createElement('span');
        span.className = 'emoji';
        span.textContent = FALLBACK_EMOJI[reward.name] || '🍬';
        img.replaceWith(span);
    };
    return img;
}

function prizeText(reward) {
    return reward.money ? `$${reward.count.toLocaleString()}` : `${reward.count}x ${reward.label}`;
}

const selected = () => state && state.days[selectedDay - 1];
const isGrand = (day) => day.day === state.days.length;

/* ---------- Sound (tiny WebAudio blips, no files needed) ---------- */

function ensureAudio() {
    if (!audio) {
        try { audio = new (window.AudioContext || window.webkitAudioContext)(); } catch { audio = null; }
    }
    return audio;
}

function blip(freq, duration, volume = 0.04, type = 'square', delay = 0) {
    const ctx = ensureAudio();
    if (!ctx) return;
    const t = ctx.currentTime + delay;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t);
    gain.gain.setValueAtTime(volume, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + duration);
    osc.connect(gain).connect(ctx.destination);
    osc.start(t);
    osc.stop(t + duration);
}

function winSound(jackpot) {
    const notes = jackpot ? [523, 659, 784, 1047, 1319] : [523, 659, 784];
    notes.forEach((f, i) => blip(f, 0.25, 0.05, 'triangle', i * 0.11));
}

/* ---------- Intensity ---------- */

function todayEntry() {
    if (!state) return null;
    const index = Math.min(Math.max(state.today, 1), state.days.length);
    return state.days[index - 1];
}

function renderEmbers(fear) {
    const container = el('embers');
    const count = Math.round(4 + fear * 28);
    if (container.childElementCount === count) return;
    container.innerHTML = '';
    for (let i = 0; i < count; i++) {
        const ember = document.createElement('span');
        ember.className = 'ember';
        ember.style.left = `${Math.random() * 100}%`;
        ember.style.animationDuration = `${6 + Math.random() * 8 - fear * 3}s`;
        ember.style.animationDelay = `${-Math.random() * 12}s`;
        ember.style.setProperty('--drift', `${(Math.random() - 0.5) * 120}px`);
        container.appendChild(ember);
    }
}

function applyIntensity() {
    const today = todayEntry();
    if (today) {
        el('fear-label').textContent = today.fear;
        el('fear-fill').style.width = `${Math.round(Math.max(0.04, today.intensity) * 100)}%`;
    }

    // The selected day drives the visuals, so peeking at later days looks scarier.
    const day = selected() || today;
    const fear = day ? day.intensity : 0;
    panel.style.setProperty('--fear', fear.toFixed(3));
    panel.classList.toggle('nightmare', fear >= 0.85);
    renderEmbers(fear);

    const live = day && (day.status === 'available' || day.status === 'pending');
    el('wheel-wrap').classList.toggle('heartbeat', !spinning && live && fear >= 0.45);
}

/* ---------- Countdown ---------- */

function renderCountdownUnits() {
    el('countdown-main').innerHTML = ['Days', 'Hours', 'Minutes', 'Seconds']
        .map((label, i) => `<div class="unit"><span id="cd-${i}">00</span><small>${label}</small></div>`)
        .join('');
}

function tick() {
    if (!state) return;
    const now = serverNow();
    const main = el('countdown-main');
    const sub = el('countdown-sub');
    const anyOpen = state.days.some((d) => d.status === 'available' || d.status === 'pending');

    const toHalloween = state.halloween - now;
    if (toHalloween <= 0 || state.phase === 'after') {
        main.classList.add('done');
        main.textContent = state.phase === 'after' && !anyOpen ? 'See you next Halloween!' : 'Happy Halloween!';
    } else {
        if (main.classList.contains('done') || !main.childElementCount) {
            main.classList.remove('done');
            renderCountdownUnits();
        }
        const t = splitTime(toHalloween);
        [t.d, t.h, t.m, t.s].forEach((v, i) => { el(`cd-${i}`).textContent = pad(v); });
    }

    if (state.nextUnlock) {
        const remaining = state.nextUnlock - now;
        if (remaining <= 0) {
            sub.textContent = 'A new spin just unlocked!';
            refresh();
        } else {
            const t = splitTime(remaining);
            const clock = `${t.d > 0 ? `${t.d}d ` : ''}${pad(t.h)}:${pad(t.m)}:${pad(t.s)}`;
            const label = state.phase === 'before' ? 'The wheel opens in' : 'Next spin unlocks in';
            sub.innerHTML = `${label} <b>${clock}</b>. The wheel gets better every day.`;
        }
    } else if (state.phase === 'active') {
        sub.textContent = 'The Halloween wheel is open. Best odds of the month!';
    } else if (state.phase === 'after') {
        sub.textContent = anyOpen ? 'Last chance! Your last spin expires at midnight.' : 'The Halloween wheel has closed.';
    } else {
        sub.textContent = '';
    }
}

async function refresh() {
    if (refreshing || spinning) return;
    refreshing = true;
    const fresh = await post('refresh');
    refreshing = false;
    if (fresh) setState(fresh);
}

/* ---------- Wheel ---------- */

function polar(angle, radius) {
    const rad = (angle * Math.PI) / 180;
    return [radius * Math.sin(rad), -radius * Math.cos(rad)];
}

function buildWheel(segments, winner) {
    const total = segments.reduce((sum, s) => sum + s.weight, 0) || 1;
    const R = 148;
    let angle = 0;
    segmentAngles = [];

    let paths = '';
    let labels = '';
    segments.forEach((seg, i) => {
        const sweep = (seg.weight / total) * 360;
        const start = angle;
        const end = angle + sweep;
        segmentAngles.push([start, end]);
        angle = end;

        const [x1, y1] = polar(start, R);
        const [x2, y2] = polar(end, R);
        const large = sweep > 180 ? 1 : 0;
        const shade = i % 2 ? 'brightness(0.82)' : 'none';
        const cls = winner === i + 1 ? 'winner' : '';
        paths += `<path class="${cls}" d="M0 0 L${x1.toFixed(2)} ${y1.toFixed(2)} A${R} ${R} 0 ${large} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z"
            fill="${seg.color}" style="filter:${shade}" stroke="rgba(0,0,0,0.35)" stroke-width="1"/>`;

        // Only draw labels where they fit; tiny slices (like a 1% jackpot) just show colour.
        const mid = start + sweep / 2;
        // Labels run along the radius (rim -> hub) so they fit narrow slices, and are
        // flipped on the left half so nothing reads upside down.
        if (sweep >= 9) {
            const flip = mid > 180;
            const text = sweep >= 12
                ? `<text class="seg-label" transform="translate(0 -84) rotate(${flip ? 90 : -90})"
                    text-anchor="middle" dominant-baseline="middle">${seg.label}</text>`
                : '';
            labels += `<g transform="rotate(${mid.toFixed(2)})">
                <text class="seg-icon" x="0" y="-128" text-anchor="middle" dominant-baseline="middle"
                    transform="rotate(${(-mid).toFixed(2)} 0 -128)">${seg.icon}</text>
                ${text}
            </g>`;
        }
    });

    wheelEl.innerHTML = `<svg viewBox="-150 -150 300 300">
        <circle r="150" fill="#120a1c"/>
        ${paths}
        ${labels}
        <circle r="148" fill="none" stroke="rgba(0,0,0,0.4)" stroke-width="3"/>
    </svg>`;
}

function setRotation(deg) {
    rotation = deg;
    wheelEl.style.transform = `rotate(${deg}deg)`;
}

/** Rotation that puts `angle` (degrees clockwise from the top of the wheel) under the pointer. */
function rotationFor(angle) {
    return ((360 - angle) % 360 + 360) % 360;
}

function segmentUnderPointer(rot) {
    const angle = ((360 - (rot % 360)) % 360 + 360) % 360;
    return segmentAngles.findIndex(([start, end]) => angle >= start && angle < end);
}

function animateTo(segment, fear) {
    const [start, end] = segmentAngles[segment - 1];
    const span = end - start;
    const target = start + span * (0.15 + Math.random() * 0.7);

    const spins = 5 + Math.round(fear * 4);
    const duration = 5000 + fear * 3500;
    const from = rotation;
    const base = Math.ceil(from / 360) * 360;
    const to = base + spins * 360 + rotationFor(target);

    // Ease out with a long, tense crawl at the end that gets longer later in the month.
    const power = 3 + fear * 2;
    const ease = (t) => 1 - Math.pow(1 - t, power);

    const pointer = el('pointer');
    let lastSegment = segmentUnderPointer(from);
    const startTime = performance.now();

    return new Promise((resolve) => {
        function frame(now) {
            const t = Math.min(1, (now - startTime) / duration);
            setRotation(from + (to - from) * ease(t));

            const current = segmentUnderPointer(rotation);
            if (current !== lastSegment) {
                lastSegment = current;
                pointer.classList.remove('tick');
                void pointer.offsetWidth;
                pointer.classList.add('tick');
                blip(700 + fear * 500, 0.03, 0.03);
            }

            if (t < 1) requestAnimationFrame(frame);
            else resolve();
        }
        requestAnimationFrame(frame);
    });
}

/* ---------- Calendar ---------- */

function setState(next) {
    state = next;
    serverOffset = state.now - Math.floor(Date.now() / 1000);

    if (!selectedDay || !state.days[selectedDay - 1]) {
        const open = state.days.find((d) => d.status === 'available' || d.status === 'pending');
        selectedDay = open ? open.day : Math.max(1, Math.min(state.today || 1, state.days.length));
    }

    renderGrid();
    renderSpinPanel();
    applyIntensity();
    tick();
}

function renderGrid() {
    const grid = el('grid');
    grid.innerHTML = '';

    state.days.forEach((day) => {
        const tile = document.createElement('div');
        tile.className = `tile ${day.status}${isGrand(day) ? ' grand' : ''}${day.day === selectedDay ? ' selected' : ''}`;
        tile.style.setProperty('--t', day.intensity.toFixed(3));
        tile.onclick = () => {
            if (spinning) return;
            selectedDay = day.day;
            renderGrid();
            renderSpinPanel();
            applyIntensity();
        };

        const num = document.createElement('span');
        num.className = 'num';
        num.textContent = day.day;
        tile.appendChild(num);

        const badges = { claimed: '✔', locked: '🔒', missed: '✖', pending: '🎁' };
        if (badges[day.status]) {
            const badge = document.createElement('span');
            badge.className = 'badge';
            badge.textContent = badges[day.status];
            tile.appendChild(badge);
        }

        // Prizes stay hidden until they have been spun.
        if (day.reward) {
            tile.appendChild(iconFor(day.reward, 'icon'));
        } else {
            const mystery = document.createElement('span');
            mystery.className = 'mystery';
            mystery.textContent = day.status === 'missed' ? '🕸️' : '🎃';
            tile.appendChild(mystery);
        }

        if (isGrand(day)) {
            const label = document.createElement('span');
            label.className = 'grand-label';
            label.textContent = 'Halloween Wheel';
            tile.appendChild(label);
        }

        grid.appendChild(tile);
    });
}

/** Days left before an open spin expires: its own day, plus the grace period. */
function expiryText(day) {
    const daysLeft = (state.graceDays || 0) - (state.today - day.day);
    if (daysLeft <= 0) return 'Last chance! Expires at midnight.';
    if (daysLeft === 1) return 'Expires at midnight tomorrow.';
    return `Expires in ${daysLeft} days.`;
}

function renderSpinPanel() {
    const day = selected();
    if (!day) return;

    el('detail-eyebrow').textContent = `Day ${day.day} · ${day.fear}`;
    el('detail-title').textContent = isGrand(day) ? 'Halloween Wheel' : `${MONTH} ${day.day}`;

    buildWheel(day.wheel, day.segment);
    wheelEl.classList.toggle('locked', day.status === 'locked' || day.status === 'missed');

    if (day.segment && segmentAngles[day.segment - 1]) {
        const [start, end] = segmentAngles[day.segment - 1];
        setRotation(rotationFor((start + end) / 2));
    } else {
        setRotation(0);
    }

    const button = el('spin');
    const note = el('detail-note');
    const views = {
        available: ['Spin the wheel', expiryText(day)],
        pending: ['Collect prize', day.reward ? `Waiting for you: ${prizeText(day.reward)}. ${expiryText(day)}` : ''],
        claimed: ['Already spun', day.reward ? `You won ${prizeText(day.reward)}.` : ''],
        locked: ['Locked', `Unlocks ${MONTH} ${day.day}. The odds get better every day.`],
        missed: ['Expired', 'This spin has expired.'],
    };
    const [label, hint] = views[day.status] || ['Unavailable', ''];
    button.textContent = spinning ? 'Spinning…' : label;
    button.disabled = spinning || (day.status !== 'available' && day.status !== 'pending');
    note.textContent = hint;
}

/* ---------- Spinning ---------- */

function showResult(result) {
    const reward = result.reward;
    const card = el('result-card');
    const jackpot = result.ok && reward.tier === 'jackpot';

    card.className = `result-card${jackpot ? ' jackpot' : ''}${result.ok ? '' : ' saved'}`;
    el('result-eyebrow').textContent = jackpot ? 'JACKPOT!' : result.ok ? 'You won!' : 'Prize saved';

    const icon = el('result-icon');
    icon.innerHTML = '';
    icon.appendChild(iconFor(reward, ''));

    el('result-title').textContent = prizeText(reward);
    const tier = el('result-tier');
    tier.textContent = reward.tierLabel || '';
    const segment = selected() && selected().wheel.find((s) => s.tier === reward.tier);
    tier.style.color = segment ? segment.color : '';
    el('result-note').textContent = result.ok ? '' : result.message || '';

    el('result').classList.remove('hidden');
    if (result.ok) winSound(jackpot);
}

async function spin() {
    const day = selected();
    if (spinning || !day || (day.status !== 'available' && day.status !== 'pending')) return;

    ensureAudio();
    spinning = true;
    renderSpinPanel();
    applyIntensity();

    const result = await post('spin', { day: day.day });

    if (result && result.segment && result.animate) {
        // Spin from the resting position so the wheel always turns a full show.
        await animateTo(result.segment, day.intensity);
        await sleep(450);
    }

    spinning = false;

    if (result && result.reward) {
        showResult(result);
    }
    if (result && result.state) {
        setState(result.state);
    } else {
        renderSpinPanel();
        applyIntensity();
    }
    if (result && !result.reward && result.message) {
        el('detail-note').textContent = result.message;
    }
}

/* ---------- Open / close ---------- */

function open(next) {
    selectedDay = null;
    el('result').classList.add('hidden');
    setState(next);
    app.classList.remove('hidden');
    clearInterval(ticker);
    ticker = setInterval(tick, 1000);
}

function hide() {
    app.classList.add('hidden');
    clearInterval(ticker);
    ticker = null;
}

function close() {
    if (spinning) return;
    hide();
    post('close');
}

el('close').addEventListener('click', close);
el('spin').addEventListener('click', spin);
el('result-ok').addEventListener('click', () => el('result').classList.add('hidden'));

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || app.classList.contains('hidden')) return;
    if (!el('result').classList.contains('hidden')) {
        el('result').classList.add('hidden');
    } else {
        close();
    }
});

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') open(data.state);
    if (data.action === 'close') hide();
});
