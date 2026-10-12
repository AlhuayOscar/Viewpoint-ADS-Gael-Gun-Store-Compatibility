/**
 * Project Viewpoint ADS - Offline Profile Generator for Gael Gun Store (B42 FBX Models).
 *
 * Scans all Gael Gun Store scripts and binary .FBX 3D models (submeshes),
 * measures weapon sight geometry (front post, rear sight notch, muzzle, and optic mounts),
 * and generates PVADS_GaelGeneratedProfiles.lua.
 *
 * Usage: node tools/gael_meshscan.js
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const GAEL_ROOT = 'C:/Program Files (x86)/Steam/steamapps/workshop/content/108600/3616176188/mods/GaelGunStore/42/media';
const MOD_ROOT_42_20 = 'C:/Users/oscarAR/Zomboid/mods/ViewpointGaelCompat/42.20/media/lua/client';
const MOD_ROOT_42 = 'C:/Users/oscarAR/Zomboid/mods/ViewpointGaelCompat/42/media/lua/client';

// -------------------------------------------------------------
// 1. Binary FBX Reader (Version 7.4/7.5)
// -------------------------------------------------------------
function readNode(buf, offset) {
    if (offset + 13 > buf.length) return null;
    const endOffset = buf.readUInt32LE(offset);
    const numProps = buf.readUInt32LE(offset + 4);
    const propListLen = buf.readUInt32LE(offset + 8);
    const nameLen = buf.readUInt8(offset + 12);
    if (endOffset === 0) return { isNull: true, nextOffset: offset + 13 };
    const name = buf.toString('utf8', offset + 13, offset + 13 + nameLen);
    let pOffset = offset + 13 + nameLen;
    const props = [];
    for (let i = 0; i < numProps; i++) {
        const type = String.fromCharCode(buf.readUInt8(pOffset++));
        if (type === 'S') {
            const len = buf.readUInt32LE(pOffset); pOffset += 4;
            props.push(buf.toString('utf8', pOffset, pOffset + len)); pOffset += len;
        } else if (type === 'R') {
            const len = buf.readUInt32LE(pOffset); pOffset += 4;
            props.push(buf.subarray(pOffset, pOffset + len)); pOffset += len;
        } else if (type === 'I') { props.push(buf.readInt32LE(pOffset)); pOffset += 4; }
        else if (type === 'C') { props.push(buf.readUInt8(pOffset++) !== 0); }
        else if (type === 'F') { props.push(buf.readFloatLE(pOffset)); pOffset += 4; }
        else if (type === 'D') { props.push(buf.readDoubleLE(pOffset)); pOffset += 8; }
        else if (type === 'L') { props.push(buf.readBigInt64LE(pOffset)); pOffset += 8; }
        else if (['f', 'd', 'i', 'l', 'b'].includes(type)) {
            const arrLen = buf.readUInt32LE(pOffset);
            const enc = buf.readUInt32LE(pOffset + 4);
            const compLen = buf.readUInt32LE(pOffset + 8);
            pOffset += 12;
            let raw = buf.subarray(pOffset, pOffset + compLen);
            pOffset += compLen;
            if (enc === 1) raw = zlib.inflateSync(raw);
            props.push({ type, arrLen, raw });
        } else {
            throw new Error('Unknown FBX prop type: ' + type);
        }
    }
    const children = [];
    while (pOffset < endOffset) {
        const child = readNode(buf, pOffset);
        if (!child || child.isNull) break;
        children.push(child);
        pOffset = child.nextOffset;
    }
    return { name, props, children, nextOffset: endOffset };
}

function parseFbx(filePath) {
    if (!fs.existsSync(filePath)) return {};
    const buf = fs.readFileSync(filePath);
    let offset = 27;
    const topNodes = {};
    while (offset < buf.length - 160) {
        const node = readNode(buf, offset);
        if (!node || node.isNull) break;
        topNodes[node.name] = node;
        offset = node.nextOffset;
    }
    const objects = topNodes['Objects'];
    const connections = topNodes['Connections'];
    if (!objects || !connections) return {};

    const geomToModel = {};
    for (const c of connections.children) {
        if (c.name === 'C' && c.props[0] === 'OO') {
            geomToModel[c.props[1].toString()] = c.props[2].toString();
        }
    }

    const models = {};
    for (const m of objects.children.filter(c => c.name === 'Model')) {
        const id = m.props[0].toString();
        const rawName = m.props[1] || '';
        const name = rawName.split('\x00\x01')[0] || rawName;
        models[id] = name;
    }

    const geoms = {};
    for (const g of objects.children.filter(c => c.name === 'Geometry')) {
        const id = g.props[0].toString();
        const vertNode = g.children.find(c => c.name === 'Vertices');
        if (vertNode) {
            const prop = vertNode.props[0];
            const raw = prop.raw;
            const points = [];
            if (prop.type === 'd') {
                for (let i = 0; i < prop.arrLen; i += 3) {
                    points.push([raw.readDoubleLE(i * 8), raw.readDoubleLE((i + 1) * 8), raw.readDoubleLE((i + 2) * 8)]);
                }
            } else if (prop.type === 'f') {
                for (let i = 0; i < prop.arrLen; i += 3) {
                    points.push([raw.readFloatLE(i * 4), raw.readFloatLE((i + 1) * 4), raw.readFloatLE((i + 2) * 4)]);
                }
            }
            geoms[id] = points;
        }
    }

    const result = {};
    for (const [geomId, modelId] of Object.entries(geomToModel)) {
        if (models[modelId] && geoms[geomId]) {
            result[models[modelId]] = geoms[geomId];
        }
    }
    return result;
}

// -------------------------------------------------------------
// 2. Script Parsers
// -------------------------------------------------------------
function parseBlocks(text) {
    const blocks = [];
    const blockRe = /^\s*(model|item)\s+([A-Za-z0-9_]+)\s*\{/gm;
    let m;
    while ((m = blockRe.exec(text)) !== null) {
        const kind = m[1];
        const name = m[2];
        const start = m.index + m[0].length;
        let depth = 1;
        let j = start;
        while (j < text.length && depth > 0) {
            if (text[j] === '{') depth++;
            else if (text[j] === '}') depth--;
            j++;
        }
        const body = text.substring(start, j - 1);
        blocks.push({ kind, name, body });
    }
    return blocks;
}

function parseModels(scriptDir) {
    const models = {};
    if (!fs.existsSync(scriptDir)) return models;
    const files = fs.readdirSync(scriptDir).filter(f => f.endsWith('.txt'));
    for (const f of files) {
        const text = fs.readFileSync(path.join(scriptDir, f), 'utf8');
        for (const b of parseBlocks(text)) {
            if (b.kind !== 'model') continue;
            const meshMatch = b.body.match(/mesh\s*=\s*([^,\r\n]+)/);
            const mesh = meshMatch ? meshMatch[1].trim() : null;
            
            const attachments = {};
            const attRe = /attachment\s+([A-Za-z0-9_]+)\s*\{([^}]*)\}/g;
            let am;
            while ((am = attRe.exec(b.body)) !== null) {
                const attName = am[1].toLowerCase();
                const attBody = am[2];
                const offMatch = attBody.match(/offset\s*=\s*([^\r\n,]+)/);
                if (offMatch) {
                    const coords = offMatch[1].trim().split(/\s+/).map(Number);
                    attachments[attName] = coords;
                }
            }
            models[b.name] = { mesh, attachments };
        }
    }
    return models;
}

function parseItems(scriptDir) {
    const items = {};
    if (!fs.existsSync(scriptDir)) return items;
    const files = fs.readdirSync(scriptDir).filter(f => f.endsWith('.txt'));
    for (const f of files) {
        const text = fs.readFileSync(path.join(scriptDir, f), 'utf8');
        for (const b of parseBlocks(text)) {
            if (b.kind !== 'item') continue;
            const d = {};
            for (const line of b.body.split('\n')) {
                const parts = line.split('=');
                if (parts.length >= 2) {
                    const k = parts[0].trim();
                    const v = parts.slice(1).join('=').trim().replace(/,$/, '');
                    d[k] = v;
                }
            }
            items[b.name] = d;
        }
    }
    return items;
}

// -------------------------------------------------------------
// 3. Geometry Solvers
// -------------------------------------------------------------
function familyFor(itemId, d) {
    const s = (d.SwingAnim || '').toLowerCase();
    const n = (itemId + ' ' + (d.DisplayName || '')).toLowerCase();
    if (s === 'handgun' || n.includes('pistol') || n.includes('revolver')) return 'pistol';
    if (n.includes('shotgun') || n.includes('spas') || n.includes('saiga')) return 'shotgun';
    if (n.includes('m60') || n.includes('m249') || n.includes('pkm') || n.includes('lmg')) return 'machinegun';
    if (n.includes('sniper') || n.includes('mosin') || n.includes('hunting') || n.includes('varmint')) return 'sniper';
    if (n.includes('mp5') || n.includes('smg') || n.includes('ump') || n.includes('uzi') || n.includes('p90')) return 'smg';
    if (n.includes('fal') || n.includes('scar') || n.includes('m14')) return 'battlerifle';
    return 'carbine';
}

function solveSights(points, muzzle) {
    if (!points || points.length === 0) return null;
    let ymin = Infinity, ymax = -Infinity;
    for (let i = 0; i < points.length; i++) {
        const y = points[i][1];
        if (y < ymin) ymin = y;
        if (y > ymax) ymax = y;
    }
    const L = ymax - ymin;
    if (L < 0.05) return null;

    const mx = muzzle ? muzzle[0] : 0;
    let minZ = Infinity, maxZ = -Infinity;
    for (let i = 0; i < points.length; i++) {
        const z = points[i][2];
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
    }
    const mz = muzzle ? muzzle[2] : (minZ + maxZ) / 2;

    // Filter points near central plane
    let near = points.filter(p => Math.abs(p[0] - mx) <= 0.007);
    if (near.length < 10) near = points.filter(p => Math.abs(p[0] - mx) <= 0.014);
    if (near.length === 0) return null;

    // Front zone (top 50% to tip - 2mm)
    const frontZone = near.filter(p => p[1] >= ymin + 0.50 * L && p[1] <= ymax - 0.002);
    if (frontZone.length === 0) return null;
    const front = frontZone.reduce((best, p) => (best === null || p[2] > best[2]) ? p : best, null);

    // Rear zone: points in rear 6% to 60% whose top is within 8mm of the front post height
    const rearZone = near.filter(p => p[1] >= ymin + 0.06 * L && p[1] <= ymin + 0.60 * L && Math.abs(p[2] - front[2]) <= 0.008);
    let rear = null;
    if (rearZone.length > 0) {
        rear = rearZone.reduce((best, p) => (best === null || p[2] > best[2]) ? p : best, null);
    } else {
        rear = [front[0], ymin + 0.20 * L, front[2]];
    }

    const r4 = arr => arr.map(v => Math.round(v * 10000) / 10000);
    return {
        front: r4(front),
        rear: r4(rear),
        length: Math.round(L * 10000) / 10000,
        sightHeight: Math.round((front[2] - mz) * 10000) / 10000
    };
}

// -------------------------------------------------------------
// 4. Optic Profiles
// -------------------------------------------------------------
function solveOpticShape(points) {
    if (!points || points.length === 0) return null;
    let minX = Infinity, maxX = -Infinity;
    let minY = Infinity, maxY = -Infinity;
    let minZ = Infinity, maxZ = -Infinity;
    for (let i = 0; i < points.length; i++) {
        const [x, y, z] = points[i];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
    const height = Math.abs(maxZ - minZ) * 0.55;
    const length = Math.abs(maxY - minY);
    const window = Math.min(Math.abs(maxX - minX), Math.abs(maxZ - minZ)) * 0.35;
    return {
        height: Math.round(height * 10000) / 10000,
        length: Math.round(length * 10000) / 10000,
        window: Math.round(window * 10000) / 10000
    };
}

// -------------------------------------------------------------
// 5. Execution and Code Generation
// -------------------------------------------------------------
console.log('--- Scanning Gael Gun Store Models & Scripts ---');

const weaponModels = parseModels(path.join(GAEL_ROOT, 'scripts/Firearms_model'));
const scopeModels = parseModels(path.join(GAEL_ROOT, 'scripts/GunPartItem'));
const allModels = { ...weaponModels, ...scopeModels };

const firearmItems = parseItems(path.join(GAEL_ROOT, 'scripts/Firearms'));
const scopeItems = parseItems(path.join(GAEL_ROOT, 'scripts/GunPartItem'));

// FBX Caches
const fbxCache = {};
function getMeshPoints(meshPath) {
    if (!meshPath) return null;
    const [filePart, submesh] = meshPath.split('|');
    if (!submesh) return null;
    
    let fbxName = path.basename(filePart);
    if (!fbxName.toLowerCase().endsWith('.fbx')) fbxName += '.fbx';
    const dirName = path.dirname(filePart);
    const fullFbxPath = path.join(GAEL_ROOT, 'models_X', dirName, fbxName);

    if (!fbxCache[fullFbxPath]) {
        fbxCache[fullFbxPath] = fs.existsSync(fullFbxPath) ? parseFbx(fullFbxPath) : {};
    }
    return fbxCache[fullFbxPath][submesh] || null;
}

// 5.1 Weapons
const weaponProfiles = {};
for (const [itemId, item] of Object.entries(firearmItems)) {
    const sprite = item.WeaponSprite || item.StaticModel;
    const m = allModels[sprite] || allModels[itemId];
    if (!m) continue;

    const meshPts = getMeshPoints(m.mesh);
    const muzzle = m.attachments['muzzle'] || null;
    const solved = meshPts ? solveSights(meshPts, muzzle) : null;
    const fam = familyFor(itemId, item);

    if (solved) {
        weaponProfiles['Base.' + itemId] = {
            family: fam,
            front: solved.front,
            rear: solved.rear,
            length: solved.length,
            sightHeight: solved.sightHeight,
            muzzle: muzzle ? muzzle.map(v => Math.round(v * 10000) / 10000) : undefined,
            scopeMount: m.attachments['scope'] ? m.attachments['scope'].map(v => Math.round(v * 10000) / 10000) : undefined
        };
    }
}

// 5.2 Optics
const opticProfiles = {};
for (const [itemId, item] of Object.entries(scopeItems)) {
    const nameLow = itemId.toLowerCase();
    const isOptic = item.Tags && item.Tags.includes('optics') || item.PartType === 'Scope' || /scope|reddot|kobra|acog|eotech|aimpoint/i.test(itemId);
    if (!isOptic) continue;

    let kind = 'reflex';
    let mag = 1.0;
    let reticle = 'dot';

    if (/x2scope/i.test(nameLow)) { kind = 'scope'; mag = 2.0; reticle = 'duplex'; }
    else if (/x4scope/i.test(nameLow) || /acog/i.test(nameLow) || /bravo4/i.test(nameLow) || /compact4x/i.test(nameLow)) { kind = 'scope'; mag = 4.0; reticle = 'chevron'; }
    else if (/x8scope/i.test(nameLow) || /ballisticscope/i.test(nameLow) || /longrange/i.test(nameLow) || /posp/i.test(nameLow)) { kind = 'scope'; mag = 8.0; reticle = 'mildot'; }
    else if (/kobra/i.test(nameLow)) { kind = 'reflex'; reticle = 'kobra_combo'; }
    else if (/okp7/i.test(nameLow)) { kind = 'reflex'; reticle = 'okp7'; }
    else if (/holo|eotech/i.test(nameLow)) { kind = 'reflex'; reticle = 'holo'; }
    else if (/tritium/i.test(nameLow)) { kind = 'iron'; reticle = 'none'; }

    const m = allModels[itemId];
    const meshPts = m ? getMeshPoints(m.mesh) : null;
    const shape = meshPts ? solveOpticShape(meshPts) : { height: 0.028, length: 0.12, window: 0.014 };

    opticProfiles['Base.' + itemId] = {
        kind,
        mag,
        reticle,
        height: shape.height,
        length: shape.length,
        window: shape.window,
        relief: kind === 'scope' ? 0.0 : 0.16,
        fovMul: kind === 'scope' ? Math.round(1.0 / Math.sqrt(mag) * 1000) / 1000 : 0.85
    };
}

console.log(`Generated profiles for ${Object.keys(weaponProfiles).length} firearms and ${Object.keys(opticProfiles).length} optics.`);

// -------------------------------------------------------------
// 6. Write Lua Output File
// -------------------------------------------------------------
function serializeLuaTable(obj, indent = 2) {
    const pad = ' '.repeat(indent);
    const entries = [];
    for (const [k, v] of Object.entries(obj)) {
        let valStr;
        if (Array.isArray(v)) {
            valStr = '{ ' + v.join(', ') + ' }';
        } else if (typeof v === 'object' && v !== null) {
            valStr = serializeLuaTable(v, indent + 2);
        } else if (typeof v === 'string') {
            valStr = JSON.stringify(v);
        } else {
            valStr = String(v);
        }
        entries.push(`${pad}["${k}"] = ${valStr}`);
    }
    return '{\n' + entries.join(',\n') + '\n' + ' '.repeat(indent - 2) + '}';
}

let luaContent = `--[[
    AUTO-GENERATED by tools/gael_meshscan.js
    3D Measured Sight Geometry & Optics for Gael Gun Store firearms.
    
    Do NOT delete PVADS_GaelSavedProfiles.lua:
    PVADS loads user calibrations and PVADS_GaelSavedProfiles.lua on TOP of these
    base profiles, preserving all your hand-tuned adjustments!
]]

require "PVADS/PVADS_Core"

PVADS = PVADS or {}
PVADS.GaelGenerated = PVADS.GaelGenerated or {}

PVADS.GaelGenerated.Weapons = ${serializeLuaTable(weaponProfiles)}

PVADS.GaelGenerated.Optics = ${serializeLuaTable(opticProfiles)}

-- Register all base weapon profiles
for weaponId, def in pairs(PVADS.GaelGenerated.Weapons) do
    PVADS.RegisterWeaponProfile(weaponId, {
        family = def.family,
        front = def.front,
        rear = def.rear,
        weaponLength = def.length,
        sightHeight = def.sightHeight,
        relief = def.family == "pistol" and 0.16 or 0.12,
        fovMul = def.family == "pistol" and 0.95 or 0.75,
    })
end

-- Register all optic profiles
for opticId, def in pairs(PVADS.GaelGenerated.Optics) do
    PVADS.RegisterOpticProfile(opticId, {
        kind = def.kind,
        mag = def.mag,
        reticle = def.reticle,
        height = def.height,
        window = def.window,
        relief = def.relief,
        fovMul = def.fovMul,
    })
end

local weaponCount = 0
for _ in pairs(PVADS.GaelGenerated.Weapons) do weaponCount = weaponCount + 1 end
local opticCount = 0
for _ in pairs(PVADS.GaelGenerated.Optics) do opticCount = opticCount + 1 end
print("[ViewpointGaelCompat] Loaded " .. tostring(weaponCount) .. " automated 3D weapon profiles and " .. tostring(opticCount) .. " optics.")
`;

// Save to all target mod directories
const targetDirs = [
    MOD_ROOT_42_20,
    MOD_ROOT_42,
    'C:/Users/oscarAR/Zomboid/Workshop/ViewpointGaelCompat/42.20/media/lua/client',
    'C:/Users/oscarAR/Zomboid/Workshop/ViewpointGaelCompat/42/media/lua/client',
    'C:/Users/oscarAR/Zomboid/Workshop/ViewpointGaelCompat/Contents/mods/ViewpointGaelCompat/42.20/media/lua/client',
    'C:/Users/oscarAR/Zomboid/Workshop/ViewpointGaelCompat/Contents/mods/ViewpointGaelCompat/42/media/lua/client',
];

for (const dir of targetDirs) {
    if (fs.existsSync(dir)) {
        fs.writeFileSync(path.join(dir, 'PVADS_GaelGeneratedProfiles.lua'), luaContent, 'utf8');
    }
}

console.log('Successfully wrote PVADS_GaelGeneratedProfiles.lua to all mod directories!');

// -------------------------------------------------------------
// 7. Solution 2: Explicit Weapon + Optic Overrides Generator
// -------------------------------------------------------------
if (process.argv.includes('--generate-overrides')) {
    console.log('\n--- Generating Solution 2: Explicit Weapon+Optic Overrides (MountOn matrix) ---');
    
    const MOUNT_HEIGHTS = {
        "ak_mount_kobra": 0.0515, "ak_mount_sag": 0.0426, "ak_mount_vpo": 0.0345, "ak_mount_xd_rgl": 0.0408,
        "AkMount": 0.0429, "ak_mount": 0.0429, "Mosin_Mount": 0.0285, "mount_mosin": 0.0285,
        "mount_rail": 0.0186, "RB7M_Mount": 0.0450, "scrap_mount": 0.0437, "scrap_mount_shotgun": 0.0440,
        "UniversalMount": 0.0369
    };
    
    const PISTOL_OPTICS = {
        "Base.MiniRedDot": true, "Base.ZaMiniRDS": true, "Base.PistolScope": true,
        "Base.Deltapoint": true, "Base.VenomRDS": true, "Base.Romeo3": true
    };

    // Find mounts applicable per weapon
    const weaponMountTypes = {};
    const mountItems = parseItems(path.join(GAEL_ROOT, 'scripts/GunPartItem'));
    for (const [mName, mItem] of Object.entries(mountItems)) {
        const mountOn = (mItem.MountOn || '').split(';').map(x => x.trim()).filter(Boolean);
        for (const w of mountOn) {
            weaponMountTypes[w] = weaponMountTypes[w] || [];
            weaponMountTypes[w].push(mName);
        }
    }

    const overrideLines = [];
    overrideLines.push('--[[ Explicit Static Weapon+Optic Overrides (Generated from MountOn matrix) ]]');
    overrideLines.push('require "PVADS/PVADS_Core"');
    overrideLines.push('');

    let pairCount = 0;
    for (const [opticId, opticItem] of Object.entries(scopeItems)) {
        const fullOpticId = 'Base.' + opticId;
        const oDef = opticProfiles[fullOpticId];
        if (!oDef) continue;

        const mountOn = (opticItem.MountOn || '').split(';').map(x => x.trim()).filter(Boolean);
        for (const fullWeaponId of mountOn) {
            const shortWeaponId = fullWeaponId.replace(/^Base\./, '');
            const wDef = weaponProfiles[fullWeaponId];
            const isPistol = wDef && wDef.family === 'pistol';

            let adjZ = 0;
            let relief = oDef.relief;
            let fovMul = oDef.fovMul;

            if (isPistol) {
                relief = 0.18;
                if (PISTOL_OPTICS[fullOpticId] || oDef.kind === 'reflex') {
                    adjZ = -0.015;
                    fovMul = 0.92;
                }
            } else {
                const mounts = weaponMountTypes[fullWeaponId] || weaponMountTypes[shortWeaponId];
                if (mounts && mounts.length > 0) {
                    const primaryMount = mounts[0];
                    const riser = MOUNT_HEIGHTS[primaryMount] || 0.025;
                    adjZ = riser;
                }
            }

            overrideLines.push(`PVADS.RegisterWeaponOpticOverride("${fullWeaponId}", "${fullOpticId}", { adjZ = ${adjZ.toFixed(4)}, relief = ${relief.toFixed(4)}, fovMul = ${fovMul.toFixed(4)} })`);
            pairCount++;
        }
    }

    const overridesFileContent = overrideLines.join('\n') + '\n';
    for (const dir of targetDirs) {
        if (fs.existsSync(dir)) {
            fs.writeFileSync(path.join(dir, 'PVADS_GaelWeaponOpticOverrides.lua'), overridesFileContent, 'utf8');
        }
    }
    console.log(`Generated ${pairCount} explicit Weapon+Optic overrides in PVADS_GaelWeaponOpticOverrides.lua!`);
}
