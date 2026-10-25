// AngelScript compile-checker for Echo templates.
// Builds: stub.as (Echo API surface) + the template under test, in one module.
#include "angelscript.h"
#include "scriptarray.h"
#include "scriptstdstring.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_errLine, g_errCol;
static char g_msg[2048];

static void Msg(const asSMessageInfo* m, void* p) {
    if (m->type == asMSGTYPE_ERROR) {
        g_errLine = m->row;
        g_errCol = m->col;
        snprintf(g_msg, sizeof(g_msg), "%s", m->message);
    }
}

static char* slurp(const char* path, long* outLen) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(n + 1);
    fread(buf, 1, n, f);
    buf[n] = 0;
    fclose(f);
    if (outLen) *outLen = n;
    return buf;
}

int main(int argc, char** argv) {
    if (argc < 2) { printf("usage: check <file.as>\n"); return 2; }

    asIScriptEngine* e = asCreateScriptEngine();
    e->SetMessageCallback(asFUNCTION(Msg), 0, asCALL_CDECL);
    RegisterScriptArray(e, false);
    RegisterStdString(e);

    long stubLen = 0, srcLen = 0;
    // The stub ships next to this source; allow an override via ECHO_STUB.
    const char* stubPath = getenv("ECHO_STUB");
    if (!stubPath || !*stubPath) stubPath = "echo_stub.as";
    char* stub = slurp(stubPath, &stubLen);
    char* src = slurp(argv[1], &srcLen);
    if (!src) { printf("OPEN FAILED\n"); return 2; }
    if (argc > 2 && strcmp(argv[2], "--nostub") == 0) { stubLen = 0; free(stub); stub = (char*)""; }

    int stubLines = 1;
    for (long i = 0; i < stubLen; i++) if (stub[i] == '\n') stubLines++;

    long total = stubLen + 1 + srcLen;
    char* combined = (char*)malloc(total + 1);
    memcpy(combined, stub, stubLen);
    combined[stubLen] = '\n';
    memcpy(combined + stubLen + 1, src, srcLen);
    combined[total] = 0;

    asIScriptModule* mod = e->GetModule("test", asGM_CREATE_IF_NOT_EXISTS);
    mod->AddScriptSection("main", combined, total);
    int r = mod->Build();
    if (r < 0) {
        // Report the error in template coordinates, not stub coordinates.
        if (g_errLine <= stubLines) {
            printf("STUB BUILD FAILED line %d col %d: %s\n", g_errLine, g_errCol, g_msg);
        } else {
            printf("BUILD FAILED line %d col %d: %s\n",
                   g_errLine - stubLines, g_errCol, g_msg);
            // Echo the offending source line for context.
            int ln = g_errLine - stubLines;
            const char* p = src;
            for (int i = 1; i < ln && p; i++) {
                const char* nl = strchr(p, '\n');
                if (!nl) break;
                p = nl + 1;
            }
            if (p) {
                const char* nl = strchr(p, '\n');
                int len = nl ? (int)(nl - p) : (int)strlen(p);
                printf("  >> %.*s\n", len, p);
            }
        }
        return 1;
    }
    printf("BUILD OK\n");
    return 0;
}
