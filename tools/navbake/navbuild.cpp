// navbuild: builds one walkable polygon mesh per ADT tile from extract.py's .tin files, with Recast.
//
//   navbuild <tin dir> <out dir> <x>_<y> [<x>_<y> ...]
//
// Frames: the .tin files are in the world frame (x north, y west, z up, yards). Recast is y-up, so a world
// point (x, y, z) is Recast (y, z, x): a cyclic swap, which keeps every triangle's winding.
// Output (<out>/<x>_<y>.tnm), little-endian:
//   "TNM1", int32 tx, ty, float cs, ch, float bmin[3] (Recast frame, the tile's own corner)
//   int32 nverts, uint16 verts[nverts*3] (cells from bmin: x, y (height in ch), z)
//   int32 npolys, int32 nvp, then per poly: uint16 verts[nvp], uint16 neis[nvp], uint8 area
//     neis: 0xffff none, < 0x8000 a poly in this tile, 0x8000 | dir a tile edge
//     (dir 0: -x (west side), 1: +z, 2: +x, 3: -z; see Recast's rcBuildPolyMesh).

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>

#include "Recast.h"

static const float TILE = 1600.0f / 3.0f;
static const float ORIGIN = 32.0f * TILE;
static const float UNIT = TILE / 128.0f;

// Agent and voxel settings, in yards. Kept here and printed into README.md's table.
// Each can be overridden from the environment (NAV_CELLS, NAV_RADIUS, ...) for tuning; bake.sh sets none.
static float envf(const char* k, float d) { const char* v = getenv(k); return v ? (float)atof(v) : d; }
static const int CELLS = (int)envf("NAV_CELLS", 500);              // cells across a tile
static const float CS = TILE / CELLS;
static const float CH = 0.25f;
static const float AGENT_HEIGHT = 2.0f;
static const float AGENT_RADIUS = envf("NAV_RADIUS", 0.6f);
static const float AGENT_CLIMB = envf("NAV_CLIMB", 2.0f);  // a step or ledge a player walks or hops up
static const float MAX_SLOPE = 50.0f;
static const int REGION_MIN = (int)envf("NAV_REGION_MIN", 600);     // cells; smaller isolated islands are dropped
static const int REGION_MERGE = (int)envf("NAV_REGION_MERGE", 1500);
static const float EDGE_ERROR = envf("NAV_EDGE_ERROR", 2.5f);      // cells
static const float EDGE_MAX = 24.0f;                               // yards

struct Chunk { float x0, y0, z0; uint64_t holes; float h[145]; };
struct Volume { float q[8]; float hmin, hmax; uint8_t area; };
struct Tin {
    std::vector<Chunk> chunks;
    std::vector<float> verts;              // world
    std::vector<int> tris;
    std::vector<uint8_t> areas;
    std::vector<Volume> volumes;
    bool ok = false;
};

static bool readAll(const std::string& path, std::vector<uint8_t>& out) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    out.resize(n);
    size_t got = fread(out.data(), 1, n, f);
    fclose(f);
    return got == (size_t)n;
}

template <class T> static T rd(const uint8_t*& p) { T v; memcpy(&v, p, sizeof(T)); p += sizeof(T); return v; }

static Tin loadTin(const std::string& path, bool objects) {
    Tin t;
    std::vector<uint8_t> buf;
    if (!readAll(path, buf) || buf.size() < 8 || memcmp(buf.data(), "TIN1", 4) != 0) return t;
    const uint8_t* p = buf.data() + 4;
    uint32_t nc = rd<uint32_t>(p);
    t.chunks.resize(nc);
    for (uint32_t i = 0; i < nc; i++) {
        Chunk& c = t.chunks[i];
        c.x0 = rd<float>(p); c.y0 = rd<float>(p); c.z0 = rd<float>(p); c.holes = rd<uint64_t>(p);
        memcpy(c.h, p, sizeof(c.h)); p += sizeof(c.h);
    }
    uint32_t nv = rd<uint32_t>(p);
    const uint8_t* vp = p; p += nv * 12;
    uint32_t nt = rd<uint32_t>(p);
    const uint8_t* tp = p; p += nt * 12;
    const uint8_t* ap = p; p += nt;
    uint32_t nvol = rd<uint32_t>(p);
    if (objects) {
        t.verts.resize(nv * 3); memcpy(t.verts.data(), vp, nv * 12);
        t.tris.resize(nt * 3); memcpy(t.tris.data(), tp, nt * 12);
        t.areas.assign(ap, ap + nt);
    }
    t.volumes.resize(nvol);
    for (uint32_t i = 0; i < nvol; i++) {
        Volume& v = t.volumes[i];
        memcpy(v.q, p, 32); p += 32;
        v.hmin = rd<float>(p); v.hmax = rd<float>(p); v.area = rd<uint8_t>(p);
    }
    t.ok = true;
    return t;
}

// Terrain of one chunk, appended in the Recast frame, keeping triangles that reach the box (world x/y).
static void addTerrain(const Chunk& c, float bx0, float by0, float bx1, float by1,
                       std::vector<float>& v, std::vector<int>& tris) {
    if (c.x0 < bx0 || c.x0 - TILE / 16 > bx1 || c.y0 < by0 || c.y0 - TILE / 16 > by1) return;
    int base = (int)v.size() / 3;
    for (int k = 0; k < 145; k++) {
        int row = k / 17, col = k % 17;
        float wx, wy;
        if (col < 9) { wx = c.x0 - row * UNIT; wy = c.y0 - col * UNIT; }
        else { wx = c.x0 - (row + 0.5f) * UNIT; wy = c.y0 - (col - 9 + 0.5f) * UNIT; }
        v.push_back(wy); v.push_back(c.z0 + c.h[k]); v.push_back(wx);
    }
    for (int r = 0; r < 8; r++)
        for (int q = 0; q < 8; q++) {
            if ((c.holes >> (r * 8 + q)) & 1) continue;
            int tl = r * 17 + q, tr = tl + 1, bl = (r + 1) * 17 + q, br = bl + 1, m = r * 17 + 9 + q;
            int t[12] = {tl, m, tr, tr, m, br, br, m, bl, bl, m, tl};
            for (int i = 0; i < 12; i++) tris.push_back(base + t[i]);
        }
}

static bool buildTile(const std::string& dir, const std::string& out, int tx, int ty) {
    char name[64];
    snprintf(name, sizeof name, "/%d_%d.tin", tx, ty);
    Tin self = loadTin(dir + name, true);
    if (!self.ok) { fprintf(stderr, "no input for %d_%d\n", tx, ty); return false; }

    const float wxmax = ORIGIN - ty * TILE, wxmin = wxmax - TILE;
    const float wymax = ORIGIN - tx * TILE, wymin = wymax - TILE;
    const int border = (int)ceilf(AGENT_RADIUS / CS) + 3;  // cells
    const float pad = border * CS;

    std::vector<float> v;
    std::vector<int> tris;
    std::vector<Volume> volumes = self.volumes;
    for (const Chunk& c : self.chunks) addTerrain(c, wxmin - pad, wymin - pad, wxmax + pad, wymax + pad, v, tris);
    for (int dx = -1; dx <= 1; dx++)
        for (int dy = -1; dy <= 1; dy++) {
            if (!dx && !dy) continue;
            snprintf(name, sizeof name, "/%d_%d.tin", tx + dx, ty + dy);
            Tin n = loadTin(dir + name, false);
            if (!n.ok) continue;
            for (const Chunk& c : n.chunks) addTerrain(c, wxmin - pad, wymin - pad, wxmax + pad, wymax + pad, v, tris);
            for (const Volume& vol : n.volumes) volumes.push_back(vol);
        }
    const int nterrain = (int)tris.size() / 3;
    const int obase = (int)v.size() / 3;
    for (size_t i = 0; i < self.verts.size(); i += 3) {
        v.push_back(self.verts[i + 1]); v.push_back(self.verts[i + 2]); v.push_back(self.verts[i]);
    }
    for (int t : self.tris) tris.push_back(obase + t);
    const int ntris = (int)tris.size() / 3, nverts = (int)v.size() / 3;

    std::vector<unsigned char> areas(ntris, 0);
    const float thr = cosf(MAX_SLOPE / 180.0f * (float)M_PI);
    for (int i = 0; i < ntris; i++) {
        const float* a = &v[tris[i * 3] * 3]; const float* b = &v[tris[i * 3 + 1] * 3]; const float* c = &v[tris[i * 3 + 2] * 3];
        float e0[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]}, e1[3] = {c[0] - a[0], c[1] - a[1], c[2] - a[2]};
        float n[3] = {e0[1] * e1[2] - e0[2] * e1[1], e0[2] * e1[0] - e0[0] * e1[2], e0[0] * e1[1] - e0[1] * e1[0]};
        float len = sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (len <= 0) continue;
        float ny = n[1] / len;
        // Terrain is wound up-facing (checked); a model's faces may be wound either way, so either side counts.
        bool walk = i < nterrain ? ny > thr : fabsf(ny) > thr;
        if (walk) areas[i] = i < nterrain ? 1 : (self.areas[i - nterrain] ? self.areas[i - nterrain] : 1);
    }

    float bmin[3] = {wymin - pad, 1e9f, wxmin - pad}, bmax[3] = {wymax + pad, -1e9f, wxmax + pad};
    for (int i = 0; i < nverts; i++) {
        float y = v[i * 3 + 1];
        if (y < bmin[1]) bmin[1] = y;
        if (y > bmax[1]) bmax[1] = y;
    }
    if (nverts == 0) { bmin[1] = 0; bmax[1] = 1; }
    bmin[1] -= 2; bmax[1] += 4;

    rcContext ctx(false);
    const int w = CELLS + border * 2, h = CELLS + border * 2;
    const int walkH = (int)ceilf(AGENT_HEIGHT / CH), walkC = (int)floorf(AGENT_CLIMB / CH), walkR = (int)ceilf(AGENT_RADIUS / CS - 0.01f);

    rcHeightfield* hf = rcAllocHeightfield();
    if (!rcCreateHeightfield(&ctx, *hf, w, h, bmin, bmax, CS, CH)) return false;
    if (!rcRasterizeTriangles(&ctx, v.data(), nverts, tris.data(), areas.data(), ntris, *hf, walkC)) return false;
    rcFilterLowHangingWalkableObstacles(&ctx, walkC, *hf);
    if (!getenv("NAV_NO_LEDGE")) rcFilterLedgeSpans(&ctx, walkH, walkC, *hf);
    rcFilterWalkableLowHeightSpans(&ctx, walkH, *hf);

    rcCompactHeightfield* chf = rcAllocCompactHeightfield();
    if (!rcBuildCompactHeightfield(&ctx, walkH, walkC, *hf, *chf)) return false;
    rcFreeHeightField(hf);
    if (!rcErodeWalkableArea(&ctx, walkR, *chf)) return false;
    const bool noVolumes = getenv("NAV_NO_VOLUMES") != nullptr;    // tuning: see what the liquid volumes change
    for (const Volume& vol : volumes) {
        if (noVolumes) break;
        float q[12];
        for (int k = 0; k < 4; k++) { q[k * 3] = vol.q[k * 2 + 1]; q[k * 3 + 1] = 0; q[k * 3 + 2] = vol.q[k * 2]; }
        rcMarkConvexPolyArea(&ctx, q, 4, vol.hmin, vol.hmax, vol.area, *chf);
    }
    if (!rcBuildDistanceField(&ctx, *chf)) return false;
    if (!rcBuildRegions(&ctx, *chf, border, REGION_MIN, REGION_MERGE)) return false;

    rcContourSet* cset = rcAllocContourSet();
    if (!rcBuildContours(&ctx, *chf, EDGE_ERROR, (int)(EDGE_MAX / CS), *cset)) return false;
    rcPolyMesh* pm = rcAllocPolyMesh();
    if (!rcBuildPolyMesh(&ctx, *cset, 6, *pm)) return false;

    snprintf(name, sizeof name, "/%d_%d.tnm", tx, ty);
    std::string tmp = out + name + std::string(".tmp");
    FILE* f = fopen(tmp.c_str(), "wb");
    if (!f) return false;
    fwrite("TNM1", 1, 4, f);
    int32_t hdr[2] = {tx, ty};
    fwrite(hdr, 4, 2, f);
    float fh[5] = {CS, CH, pm->bmin[0], pm->bmin[1], pm->bmin[2]};
    fwrite(fh, 4, 5, f);
    int32_t nv = pm->nverts, np = pm->npolys, nvp = pm->nvp;
    fwrite(&nv, 4, 1, f);
    fwrite(pm->verts, 2, nv * 3, f);
    fwrite(&np, 4, 1, f);
    fwrite(&nvp, 4, 1, f);
    for (int i = 0; i < np; i++) {
        fwrite(&pm->polys[i * nvp * 2], 2, nvp * 2, f);
        fwrite(&pm->areas[i], 1, 1, f);
    }
    fclose(f);
    rename(tmp.c_str(), (out + name).c_str());
    printf("%d_%d polys %d verts %d tris %d\n", tx, ty, np, nv, ntris);
    rcFreeCompactHeightfield(chf);
    rcFreeContourSet(cset);
    rcFreePolyMesh(pm);
    return true;
}

int main(int argc, char** argv) {
    if (argc < 4) { fprintf(stderr, "usage: navbuild <tin dir> <out dir> <x>_<y> ...\n"); return 2; }
    int bad = 0;
    for (int i = 3; i < argc; i++) {
        int x, y;
        if (sscanf(argv[i], "%d_%d", &x, &y) != 2) { bad++; continue; }
        if (!buildTile(argv[1], argv[2], x, y)) { fprintf(stderr, "failed %s\n", argv[i]); bad++; }
    }
    return bad ? 1 : 0;
}
