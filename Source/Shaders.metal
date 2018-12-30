#include <metal_stdlib>
#import "Shader.h"

using namespace metal;

float2 functionCall(float2 old,constant Function *func);

kernel void fractalShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 device TVertex* vData      [[ buffer(0) ]],
 constant Control &control  [[ buffer(1) ]],
 uint2 p [[thread_position_in_grid]])
{
    uint2 srcP = p;

    if(control.radialAngle > 0.01) { // 0 = don't apply
        float centerX = control.xSize/2;
        float centerY = control.ySize/2;
        float dx = float(p.x - centerX);
        float dy = float(p.y - centerY);
        
        float angle = fabs(atan2(dy,dx));
        
        float dRatio = 0.01 + control.radialAngle;
        while(angle > dRatio) angle -= dRatio;
        if(angle > dRatio/2) angle = dRatio - angle;
        
        float dist = sqrt(dx * dx + dy * dy);
        
        srcP.x = uint(centerX + cos(angle) * dist);
        srcP.y = uint(centerY + sin(angle) * dist);
    }
    
    float2 z;
    
    // screen size not evenly divisible by threadGroups?
    if(control.is3DWindow == 0) {        // 2D fractal in Main window
        if(p.x >= uint(control.xSize)) return;
        if(p.y >= uint(control.ySize)) return;
        z = float2(control.xmin + control.dx * float(srcP.x), control.ymin + control.dy * float(srcP.y));
        
        if(control.win3DFlag > 0) {  // draw 3D bounding box
            bool mark = false;
            if(z.x >= control.xmin3D && z.x <= control.xmax3D) {
                if(z.y >= control.ymin3D && z.y <= control.ymin3D + control.dy) mark = true; else
                    if(z.y >= control.ymax3D && z.y <= control.ymax3D + control.dy) mark = true;
            }
            if(!mark) {
                if(z.y >= control.ymin3D && z.y <= control.ymax3D) {
                    if(z.x >= control.xmin3D && z.x <= control.xmin3D + control.dx) mark = true; else
                        if(z.x >= control.xmax3D && z.x <= control.xmax3D + control.dx) mark = true;
                }
            }
            
            if(mark) {
                outTexture.write(float4(1,1,1,1),p);
                return;
            }
        }
    }
    else {  // 3D rendition in second window
        if(p.x >= uint(SIZE3D)) return;
        if(p.y >= uint(SIZE3D)) return;
        z = float2(control.xmin3D + control.dx3D * float(srcP.x), control.ymin3D + control.dy3D * float(srcP.y));
    }

    int iter;
    float avg = 0;
    float lastAdded = 0;
    float z2 = 0;
    int gIndex = 0;
    int chr;
    const int maxIter = 32;
    
    for(iter = 0;iter < maxIter;++iter) {
        // round-robin function index from grammar string
        chr = int(control.grammar[gIndex++]) - 49; // 49 = ASCII offset '1'
        if(gIndex >= MAX_GRAMMER) gIndex = 0;
        if(chr < 0) {                   // terminating zero -> -49
            gIndex = 0;
            chr = int(control.grammar[gIndex++]) - 49;
        }
        z = functionCall(z, &control.function[chr]);
        
        // translate
        z.x += control.function[chr].xT;
        z.y += control.function[chr].yT;
        
        // rotate
        if(control.function[chr].rot != 0) {
            float qt = z.x;
            float ss = sin(control.function[chr].rot);
            float cc = cos(control.function[chr].rot);
            z.x = z.x * cc - z.y * ss;
            z.y = qt * ss + z.y * cc;
        }
        
        // scale
        z.x *= control.function[chr].xS;
        z.y *= control.function[chr].yS;
        
        lastAdded = 0.5 + 0.5 * sin(control.stripeDensity * atan2(z.y, z.x));
        avg += lastAdded;
        
        z2 = dot(z,z);
        if (z2 > control.escapeRadius) break;
    }
    
    float3 icolor = float3();
    
    if(iter > 1) {
        float prevAvg = (avg - lastAdded) / (iter - 1.0);
        avg = avg / iter;
        
        float frac = 1.0 + (log2(log(control.escapeRadius) / log(z2)));
        float mix = frac * avg + (1.0 - frac) * prevAvg;
        
        if(iter < maxIter) {
            float co = mix * pow(10.0,control.multiplier);
            co = clamp(co,0.0,10000.0) * 6.2831;
            icolor.x = 0.5 + 0.5 * cos(co + control.color.x);
            icolor.y = 0.5 + 0.5 * cos(co + control.color.y);
            icolor.z = 0.5 + 0.5 * cos(co + control.color.z);
        }
    }
    
    icolor.x = 0.5 + (icolor.x - 0.5) * control.contrast;
    icolor.y = 0.5 + (icolor.y - 0.5) * control.contrast;
    icolor.z = 0.5 + (icolor.z - 0.5) * control.contrast;
    
    if(control.is3DWindow == 0) {        // 2D fractal in Main window
        outTexture.write(float4(icolor,1),p);
    }
    else {  // 3D rendition in second window
        if(icolor.x < 0.1 && icolor.y < 0.1 && icolor.z < 0.1) icolor = float3(0.3);
        
        int index = int(SIZE3D - 1 - p.y) * SIZE3D + int(p.x);
        vData[index].color = float4(icolor,1);
        vData[index].height = float(iter);
    }
}

// ======================================================================

kernel void shadowShader
(
 texture2d<float, access::read> src [[texture(0)]],
 texture2d<float, access::write> dst [[texture(1)]],
 uint2 p [[thread_position_in_grid]])
{
    float4 v = src.read(p);
    
    if(p.x > 1 && p.y > 1) {
        bool shadow = false;
        
        {
            uint2 p2 = p;
            p2.x -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.x -= 1;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(shadow) {
            v.x /= 4;
            v.y /= 4;
            v.z /= 4;
        }
    }
    
    dst.write(v,p);
}

// random float in range [0.0f, 1.0f] (based on the xor128 algorithm)
float rand(float y, float z) {
    int seed = 13 + int(y * 1000) * 57 + int(z * 1000) * 241;
    seed = (seed << 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

int modn(int n, int m ) { return ( (n % m) + m ) % m; }

float2 functionCall(float2 old, constant Function *func) {
    const float pi = 3.141592654;
    float2 pt = old;
    
    switch(func->index) {
        case 0 : // linear
            break;
        case 1 : // 'Sinusoidal'
            pt.x = sin(pt.x);
            pt.y = sin(pt.y);
            break;
        case 2 : // 'Spherical'
        {
            float r = length(pt);
            float den = pow(r,2);
            pt.x /= den;
            pt.y /= den;
        }
            break;
        case 3 : // 'Swirl'
        {
            float r = length(pt);
            float den = pow(r,2);
            pt.x = (old.x * sin(den)) - (old.y * cos(den));
            pt.y = (old.x * cos(den)) + (old.y * sin(den));
        }
            break;
        case 4 : // 'Horseshoe'
        {
            float r = length(old);
            pt.x = ( 1 / r ) * ( old.x - old.y ) * ( old.x + old.y );
            pt.y = ( 1 / r ) * 2 * old.x * old.y;
        }
            break;
        case 5 : // 'Polar'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = th / pi;
            pt.y = r - 1;
        }
            break;
        case 6 : // 'Hankerchief'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = r * sin(th + r);
            pt.y = r * cos(th - r);
        }
            break;
        case 7 : // 'Heart'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = r * sin( th * r );
            pt.y = r * -cos( th * r );
        }
            break;
        case 8 : // 'Disc'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = ( th / pi ) * sin(pi * r );
            pt.y = ( th / pi ) * cos(pi * r );
        }
            break;
        case 9 : // 'Spiral'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = ( 1 / r ) * ( cos(th) + sin(r) );
            pt.y = ( 1 / r ) * ( sin(th) - cos(r) );
        }
            break;
        case 10 : // 'Hyperbolic'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = sin(th) / r;
            pt.y = r * cos(th);
        }
            break;
        case 11 : // 'Diamond'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            pt.x = sin(th) * cos(r);
            pt.y = cos(th) * sin(r);
        }
            break;
        case 12 : // 'Ex'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            float p0 = sin( th + r );
            float p1 = cos( th - r );
            pt.x = r * ( pow( p0, 3 ) + pow( p1, 3 ) );
            pt.y = r * ( pow( p0, 3 ) - pow( p1, 3 ) );
        }
            break;
        case 13 : // 'Julia'
        {
            float rs = sqrt(length(pt));
            float th = atan2(pt.y,pt.x);
            float om = func->xT || ( func->xT + func->rot + func->xS + func->yT + func->yS );
            pt.x = rs * cos( th / 2 + om );
            pt.y = rs * sin( th / 2 + om );
        }
            break;
        case 14 : // 'JuliaN',
        {
            float r = length(pt);
            float ph = atan2(pt.x,pt.y);
            float p1 = 1;
            float p2 = 0.75;
            float rrnd = func->xT + 0.5; //  || 0.5;
            float p3 = trunc( abs( p1 ) * rrnd );
            float t = ( ph + ( 2 * pi * p3 ) ) / p1;
            float rpp = pow( r, p2/p1 );
            pt.x = rpp * cos( t );
            pt.y = rpp * sin( t );
        }
            break;
        case 15 : // 'Bent'
        {
            if(pt.x >= 0 && pt.y >= 0 ) break;
            if(pt.x < 0 && pt.y >= 0) {
                pt.x *= 2;
            }
            else if( pt.x >= 0 && pt.y < 0 ) {
                pt.y /= 2;
            }
            else {
                pt.x *= 2;
                pt.y /= 2;
            }
        }
            break;
        case 16 : // 'Waves'
            pt.x = old.x + ( func->rot * sin( old.y / pow( func->xS, 2 )));
            pt.y = old.y + ( func->rot * sin( old.x / pow( func->yS, 2 )));
            break;
        case 17 : // 'Fisheye'
        {
            float re = 2 / ( sqrt( pow( old.x, 2 ) + pow( old.y, 2 ) ) + 1 );
            pt.x = re * old.y;
            pt.y = re * old.x;
        }
            break;
        case 18 : // 'Popcorn'
            pt.x = old.x + ( func->xS * sin( tan( 3 * old.y )));
            pt.y = old.y + ( func->yS * sin( tan( 3 * old.x )));
            break;
        case 19 : // 'Power'
        {
            float th = atan2( old.y, old.x );
            float rsth = pow( sqrt( pow( old.x, 2 ) + pow( old.y, 2 ) ), sin(th) );
            pt.x = rsth * cos(th);
            pt.y = rsth * sin(th);
        }
            break;
        case 20 : // 'Rings'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            float re = modn( ( r + pow( func->xS, 2 ) ), ( 2 * pow( func->xS, 2 ) ) ) - pow( func->xS, 2 ) + ( r * ( 1 - pow( func->xS, 2 )));
            pt.x = re * cos(th);
            pt.y = re * sin(th);
        }
            break;
        case 21 : // 'Fan'
        {
            float r = length(pt);
            float th = atan2(pt.y,pt.x);
            float t = pi * pow( func->xS, 2 );
            if( modn( ( th + func->yS ), t ) > ( t / 2 ) ) {
                pt.x = r * cos( th - ( t / 2 ) );
                pt.y = r * sin( th - ( t / 2 ) );
            }
            else {
                pt.x = r * cos( th + ( t / 2 ) );
                pt.y = r * sin( th + ( t / 2 ) );
            }
        }
            break;
        case 22 : // 'Eyefish'
        {
            float  re = 2 / ( sqrt( pow( pt.x, 2 ) + pow( pt.y, 2 ) ) + 1 );
            pt.x *= re;
            pt.y *= re;
        }
            break;
        case 23 : // 'Bubble'
        {
            float re = 4 / ( pow( sqrt( pow( pt.x, 2 ) + pow( pt.y, 2 ) ), 2 ) + 4 );
            pt.x *= re;
            pt.y *= re;
        }
            break;
        case 24 : // 'Cylinder'
            pt.x = sin(pt.y);
            break;
        case 25 : // 'Tangent'
            pt.x = sin(pt.x) / cos(pt.y);
            pt.y = tan(pt.y);
            break;
        case 26 : // 'Cross',
        {
            float s = sqrt( 1 / pow( pow( pt.x, 2 ) - pow( pt.y, 2 ), 2 ) );
            pt.x *= s;
            pt.y *= s;
        }
            break;
        case 27 : // 'Noise'
        {
            float lastRandom = old.x * 10240 + old.y * 12345;
            lastRandom = rand(lastRandom,pt.x);
            float p1 = lastRandom;
            lastRandom = rand(lastRandom,pt.y);
            float p2 = lastRandom;
            pt.x = p1 * pt.x * cos( 2 * pi * p2 );
            pt.y = p1 * pt.y * sin( 2 * pi * p2 );
        }
            break;
        case 28 : // 'Blur'
        {
            float lastRandom = old.x * 10240 + old.y * 12345;
            lastRandom = rand(lastRandom,pt.x);
            float p1 = lastRandom;
            lastRandom = rand(lastRandom,pt.y);
            float p2 = lastRandom;
            pt.x = p1 * cos( 2 * pi * p2 );
            pt.y = p1 * sin( 2 * pi * p2 );
        }
            break;
        case 29 : // 'Square'
        {
            float lastRandom = old.x * 10240 + old.y * 12345;
            lastRandom = rand(lastRandom,pt.x);
            float p1 = lastRandom;
            lastRandom = rand(lastRandom,pt.y);
            float p2 = lastRandom;
            pt.x = p1 - 0.5;
            pt.y = p2 - 0.5;
        }
            break;
    }
    
    return pt;
}

/////////////////////////////////////////////////////////////////////////

struct Transfer {
    float4 position [[position]];
    float4 lighting;
    float4 color;
};

vertex Transfer texturedVertexShader
(
 constant TVertex *data[[ buffer(0) ]],
 constant Uniforms &uniforms[[ buffer(1) ]],
 unsigned int vid [[ vertex_id ]])
{
    TVertex in = data[vid];
    Transfer out;
    
    out.color = in.color;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    
    float distance = length(uniforms.light.position - in.position.xyz);
    float intensity = uniforms.light.ambient + saturate(dot(in.normal.rgb, uniforms.light.position) / pow(distance,uniforms.light.power) );
    out.lighting = float4(intensity,intensity,intensity,1);
    
    return out;
}

fragment float4 texturedFragmentShader
(
 Transfer data [[stage_in]])
{
    return data.color * data.lighting;
}

/////////////////////////////////////////////////////////////////////////

kernel void normalShader
(
 device TVertex* v [[ buffer(0) ]],
 uint2 p [[thread_position_in_grid]])
{
    if(p.x >= SIZE3D || p.y >= SIZE3D) return; // data size not evenly divisible by threadGroups
    
    int i = int(p.y) * SIZE3D + int(p.x);
    int i2 = i + ((p.x < SIZE3Dm) ? 1 : -1);
    int i3 = i + ((p.y < SIZE3Dm) ? SIZE3D : -SIZE3D);
    
    TVertex v1 = v[i];
    TVertex v2 = v[i2];
    TVertex v3 = v[i3];
    
    v[i].normal = normalize(cross(v1.position - v2.position, v1.position - v3.position));
}

/////////////////////////////////////////////////////////////////////////

kernel void smoothingShader
(
 constant TVertex* src      [[ buffer(0) ]],
 device TVertex* dst        [[ buffer(1) ]],
 constant Control &control  [[ buffer(2) ]],
 uint2 p [[thread_position_in_grid]])
{
    int2 pp = int2(p);
    
    if(pp.x >= SIZE3D || pp.y >= SIZE3D) return; // data size not evenly divisible by threadGroups
    
    int index = pp.y * SIZE3D + pp.x;
    
    // determine average height of neighbors
    int count = 0;
    float totalHeight = 0;
    
    for(int x = -4; x <= 4; ++x) {
        if(pp.x + x < 0) continue;
        if(pp.x + x > SIZE3Dm) continue;
        
        for(int y = -4; y <= 4; ++y) {
            if(pp.y + y < 0) continue;
            if(pp.y + y > SIZE3Dm) continue;
            
            int index2 = index + y * SIZE3D + x;
            totalHeight += src[index2].height;
            
            ++count;
        }
    }
    
    float averageHt = totalHeight / float(count);
    
    // smoothed height
    float delta = 1 - control.smooth;
    float ht = src[index].height * control.smooth + averageHt * delta; //  * 25) / (1 + delta * 25);
    
    TVertex v = src[index];
    v.position.y = ht * control.height / 3.0;
    
    dst[index] = v;
}

