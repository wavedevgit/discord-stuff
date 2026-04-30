import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Agent } from 'node:https';

const REPO = 'Discord-Datamining/Discord-Datamining';
const API = `https://api.github.com/repos/${REPO}/commits`;

const OUT_DIR = '../data/dp';
const PER_PAGE = 100;

/*
  tune this depending on your internet
  too high = github/disc gets angry
*/
const CONCURRENCY = 10;

const githubHeaders = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'Mozilla/5.0',
};

if (process.env.GITHUB_TOKEN) {
    githubHeaders.Authorization = `Bearer ${process.env.GITHUB_TOKEN.trim().replace(
        '\n',
        '',
    )}`;
}

/*
  keep-alive matters a LOT here
  otherwise you're reconnecting constantly like a goblin
*/
const agent = new Agent({
    keepAlive: true,
    maxSockets: CONCURRENCY,
});

async function fetchJson(url, headers = {}) {
    const res = await fetch(url, {
        headers,
        agent,
    });

    if (!res.ok) {
        throw new Error(`HTTP ${res.status} :: ${url}`);
    }

    return res.json();
}

async function fetchText(url, headers = {}) {
    const res = await fetch(url, {
        headers,
        redirect: 'follow',
        agent,
    });

    return {
        status: res.status,
        text: await res.text(),
    };
}

function extractBuild(message) {
    const match = message.match(/Build\s*([0-9]+)\s*\(([a-f0-9]{40})\)/i);

    if (!match) return null;

    return {
        build: match[1],
        hash: match[2],
    };
}

async function processCommit(commit) {
    const parsed = extractBuild(commit.commit.message);
    if (!parsed) return;

    const out = join(OUT_DIR, commit.sha);

    await mkdir(out, { recursive: true });

    await writeFile(join(out, 'info.json'), JSON.stringify(parsed, null, 2));

    const url = `https://canary.discord.com/overlay?build_id=${parsed.hash}`;

    try {
        const res = await fetchText(url, {
            'User-Agent': 'Mozilla/5.0',
        });

        if (res.status === 200) {
            await writeFile(join(out, 'index.html'), res.text);
        } else if (res.status === 404) {
            await writeFile(join(out, 'index.html'), 'no_html_found_here');
        } else {
            await writeFile(join(out, 'index.html'), `error ${res.status}`);
        }
    } catch (err) {
        await writeFile(join(out, 'index.html'), `fetch_error: ${err.message}`);
    }
}

async function worker(queue) {
    while (queue.length) {
        const item = queue.shift();
        if (!item) break;

        try {
            await processCommit(item);
        } catch (err) {
            console.error('commit failed:', item.sha, err.message);
        }
    }
}

async function main() {
    await mkdir(OUT_DIR, { recursive: true });

    let page = 1;

    while (true) {
        console.log(`fetching page ${page}`);

        const commits = await fetchJson(
            `${API}?per_page=${PER_PAGE}&page=${page}`,
            githubHeaders,
        );

        if (!commits.length) {
            console.log('done');
            break;
        }

        /*
      pre-filter before queueing
      saves a lot of pointless work
    */
        const queue = commits.filter((c) =>
            /Build\s*[0-9]+\s*\([a-f0-9]{40}\)/i.test(c.commit.message),
        );

        const workers = Array.from({ length: CONCURRENCY }, () =>
            worker(queue),
        );

        await Promise.all(workers);

        page++;
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
