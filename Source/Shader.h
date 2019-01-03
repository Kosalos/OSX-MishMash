#pragma once

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

#define SIZE3D 255
#define SIZE3Dm (SIZE3D - 1)

#define NUM_FUNCTION 4
#define MAX_GRAMMER 12

typedef struct {
    int index;
    float xT,yT;
    float xS,yS;
    float rot;
    float unused[4];
} Function;

typedef struct {
    float x,y;
    int active;
} PointOrbitTrap;

typedef struct {
    float x,y;
    float slope;
    int active;
} LineOrbitTrap;

typedef struct {
    int version;
    int xSize,ySize;
    
    float xmin,xmax,dx;
    float ymin,ymax,dy;

    char grammar[MAX_GRAMMER+1];
    Function function[NUM_FUNCTION];

    float maxIter;
    float skip;
    float stripeDensity;
    float escapeRadius;
    float multiplier;
    vector_float3 color;
    float contrast;
    
    PointOrbitTrap pTrap[3];
    LineOrbitTrap lTrap[3];
    
    float power;
    float foamQ;
    float foamW;
    
    int is3DWindow;
    int win3DFlag;
    int xSize3D,ySize3D;
    float xmin3D,xmax3D,dx3D;
    float ymin3D,ymax3D,dy3D;
    float height;
    float smooth;
    
    float radialAngle;
} Control;

typedef struct {
    vector_float3 position;
    vector_float3 normal;
    vector_float2 texture;
    vector_float4 color;
    float height;
} TVertex;

typedef struct {
    int count;
} Counter;

typedef struct {
    vector_float3 base;
    float radius;
    float deltaAngle;
    float power;        // 1 ... 3
    float ambient;
    float height;
    
    vector_float3 position;
    float angle;
} LightData;

typedef struct {
    matrix_float4x4 mvp;
    float pointSize;
    LightData light;
} Uniforms;

#ifndef __METAL_VERSION__

void setControlPointer(Control *ptr);

void controlRandom(void);
void controlRandomGrammar(void);
void controlInitAutoMove(void);
void controlAutoMove(void);

char *controlDebugString(void);
void setGrammarCharacter(int index, char chr);
int  getGrammarCharacter(int index);

int getEquationIndex(int fIndex);
void setEquationIndex(int fIndex, int index);
float* funcXtPointer(int fIndex);
float* funcYtPointer(int fIndex);
float* funcXsPointer(int fIndex);
float* funcYsPointer(int fIndex);
float* funcRotPointer(int fIndex);
int isFunctionActive(int index);

#endif

