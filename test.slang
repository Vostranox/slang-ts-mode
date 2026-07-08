#define MAX_LIGHTS 16
#include "common.slangh"

__exported import Graphics.Core;
import Utils;

namespace Demo
{

    enum LightKind : int
    {
        Directional = 0,
        Point = 1,
        Spot = 2,
    }

    interface IShape
    {
        associatedtype Payload : IDifferentiable;

        property int count { get; set; }

        float area(This other);
    }

    struct Light
    {
        float3 position : POSITION;
        float3 color : COLOR0;
        uint flags;

        property highBits : uint
        {
            get { return flags >> 16; }
            set { flags = (flags & 0xFFFF) | (newValue << 16); }
        }
    }

    struct Sphere : IShape
    {
        typedef float Payload;
        float radius;
        static const float kPi = 3.14159265f;

        __init(float r)
        {
            radius = r;
        }

        __subscript(int index) -> float
        {
            get { return radius * index; }
            set { radius = newValue; }
        }

        float area(This other)
        {
            return 4.0f * kPi * radius * radius + other.radius;
        }
    }

    extension Sphere : IPrintable
    {
        void print()
        {
            printf("sphere %f\n", this.radius);
        }
    }

} // namespace Demo

ConstantBuffer<Demo.Light> gLight;
StructuredBuffer<float4> gPositions;
RWTexture2D<float4> gOutput;
SamplerState gSampler;
Texture2D gAlbedo;

T genericMax<T : IArithmetic>(T a, T b)
{
    return a > b ? a : b;
}

void constrained<T>(T value)
    where T : IShape,
        T : IDifferentiable
{
}

float evalLight(uniform Demo.Light light, float3 normal)
{
    var contribution = dot(normal, light.position);
    let scale : float = 0.5f;
    var kind : int = 1;

    if (light is DirectionalLight)
    {
        let directional = light as DirectionalLight;
    }

    switch (kind)
    {
    case 0:
        contribution += scale;
        break;
    default:
        contribution *= 2.0;
        break;
    }

    for (int i = 0; i < MAX_LIGHTS; ++i)
    {
        contribution += 0.125f;
    }

    while (contribution < 0.0f)
    {
        contribution = -contribution;
    }

    return saturate(contribution);
}

[shader("fragment")]
float4 fragmentMain(float3 normal : NORMAL, float2 uv : TEXCOORD0)
    : SV_Target
{
    if (gLight.flags == 0u)
        discard;

    float4 albedo = gAlbedo.Sample(gSampler, uv);
    float ndotl = evalLight(gLight, normalize(normal));
    return albedo * ndotl + float4(0.0, 0x10 / 255.0, 1e-3, 1.0f);
}

[numthreads(8, 8, 1)]
void computeMain(uint3 tid : SV_DispatchThreadID)
{
    gOutput[tid.xy] = fragmentMain(float3(0, 1, 0), float2(tid.xy) / 512.0f);
}
