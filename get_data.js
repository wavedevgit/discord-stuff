const fs = require('fs/promises');
(async () => {
    const desktop = await fs.readdir('./data/wayback_changelogs/desktop');
    const mobile = await fs.readdir('./data/wayback_changelogs/mobile');
    const old = JSON.parse(
        await fs.readFile('./data/changelogs_merged.json', 'utf-8'),
    );
    const oldc = old.length;
    const download = async (config, type) => {
        const types = { desktop: 0, mobile: 1 };
        let output = [];
        for (let id in config) {
            console.log(id, type);
            let content = await (
                await fetch(
                    `https://cdn.discordapp.com/changelogs/${types[type]}/${id}/en-US.json`,
                )
            ).json();
            output.push({ ...content, ...config[id], type });
        }
        return output;
    };
    const process = async (item, type) => {
        for (let file of item) {
            const content = JSON.parse(
                await fs.readFile(
                    './data/wayback_changelogs/' + type + '/' + file,
                    'utf-8',
                ),
            );
            old.push(...(await download(content, type)));
        }
    };
    await process(desktop, 'desktop');
    await process(mobile, 'mobile');
    console.log('got ', old.length - oldc, 'entries.');
    await fs.writeFile(
        './data/changelogs_merged.json',
        JSON.stringify(old, null, 4),
        'utf-8',
    );
})();
