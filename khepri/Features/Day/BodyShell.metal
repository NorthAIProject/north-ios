#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// The body figure's skin as an outline only: clear where it faces the
// camera, firm at the silhouette, so the muscles inside read as the body and
// the skin as its edge. The web viewer's rim (viewer.js addRim, with
// SHELL_EDGE_ALPHA and SHELL_EDGE_POWER) in RealityKit's terms.
//
// custom_parameter: x the edge's opacity, y its power (higher is a thinner
// edge), z how strongly the emissive colour lights the edge.
[[visible]]
void bodyShellOutline(realitykit::surface_parameters params)
{
    float4 knobs = params.uniforms().custom_parameter();
    float3 normal = normalize(params.geometry().normal());
    float3 view = normalize(params.geometry().view_direction());
    float rim = pow(1.0 - abs(dot(normal, view)), knobs.y);

    auto constants = params.material_constants();
    auto surface = params.surface();
    surface.set_base_color(half3(constants.base_color_tint()));
    surface.set_emissive_color(half3(constants.emissive_color() * rim * knobs.z));
    surface.set_roughness(half(constants.roughness_scale()));
    surface.set_metallic(0);
    surface.set_opacity(half(min(1.0, rim * knobs.x)));
}
