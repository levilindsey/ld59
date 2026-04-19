# Ludum Dare 59: "Signals"

## Brainstorming

### echolocation in a dark world and resonance frequencies

- It's a 2D platformer game.
- Player:
    - You are a flying creature. Holding jump triggers a periodic upward jump pulse.
        - I should already have action-handler logic to support this.
- Echolocation:
    - We always render the background, tiles, and objects in a small radius around the player.
        - This visibility attenuates with distance.
    - We then also render more tiles and objects around the player at a much greater distance when they activite their echolocation ability.
        - However, we render shapes differently in this mode, with a fun shader.
            - We'll need to explore options for what will look good for this.
            - Probably something resembling some sort of pointillism effect.
            - Dithering will probably work well for this.
            - Additionally, we should render tile surfaces more strongly than tile interiors.
                - There should be some sort of gradual attenuation for this in the shader.
        - This also will attenuate, but at a greater distance.
            - Meaning, we stop rendering any tiles at a distance, regardless of whether they are surface or interior tiles.
    - This echolocation ability could be directional, with an angular spread, or in a circular radius all around the player.
        - We'll need to prototype and experiment with what feels good.
        - Possibly, we'll be able to switch dynamically at run time.
    - There will be different types/frequencies/colors of echolocation.
- Tiles:
    - We'll have statically defined levels.
    - We'll need to be able to record for each tile in our marching-squares-based system the current health of that tile.
        - Discrete, int-based values.
    - We'll also need to record the _type_ of that tile.
        - There will be a type matching each echolocation type.
        - There will also be an indestructible type.
        - There will also be a liquid and/or sand type.
            - We'll want to add some sort of flow simulation logic for this type.
                - Sand would pile up, and water would pool.
            - If the player is hit by falling tiles, they take damage, and/or get swept downward.
            - Also, possibly, any terrain type will fall if it loses enough supporting neighbors.
                - The rule for this might be if it is in a contiguous chunk with an area less than a threshold.
            - I assume falling tiles need to be represented differently than stationary tiles that are part of the marching-squares system.
    - Additionally, there will be other props that are solid (not destructible). They'll be rigid bodies that simulate physics, so they'll fall when their foundation disappears.
    - Triggering echolocation might damage tiles.
        - More damage for a stronger pulse.
            - Closer/less-attenuated is stronger.
        - Only echolocation of the matching type/color will damage a tile.
- Bugs:
    - Bugs appear, move a bit, and disappear.
    - They generate a signal of their own, so you can always see them (via another pointillism/dithering shader effect) from a medium distance--further than normal vision and less far than echolocation.
        - Echolocation makes them even more visible though.
    - We need to indicate when they are appearing and disappearing.
        - Probably with a simple opacity transitition.
    - Bugs are food!
    - You eat them just by touching them.
    - Bugs have different types/colors.
    - When you eat a bug of a color, you change to that type/frequency of echolocation.
    - Bugs spawn at random locations within a certain distance range from you.
        - Neither too close nor too far.
    - We'll configure regions in the level.
        - A region adds or subtracts to the spawn rate for a given bug type.
        - We should be able to stack rates by overlapping regions.
    - We'll determine the current spawn rate for all types based on the _player's_ current position. We then spawn bugs at the calculated rates all around the player--within the radial range.
        - This means a bug could spawn in a position that is outside of the spawn-rate-region that affected its spawn--it's whether the player is in the spawn-rate-region that matters.
    - Bugs also give a little health boost to the player when eaten.
- Enemies:
    - Types:
        - Big scary monster birds
        - Spiders
        - Smaller flying somethings
    - Enemies have health (discrete, int-based).
    - Enemies have colors that match echolocation frequency types.
    - Each type of enemy can be any of the different colors.
    - Echolocation deals damage to enemies of the matching type, similar to tiles.
    - All enemies are attracted to the player.
    - Enemies will need to track some sort of perception score.
        - When they strongly perceive the player, they more aggressively approach.
        - Or maybe perception is just binary. Probably simpler that way.
    - Time and/or distance should make an enemy stop perceiving the player.
    - The player takes damage when touching an enemy.
    - Enemies should perceive echolocation.
    - When damaged by echolocation, an enemy is knocked-back.
    - Most enemies spawn once at specific spawn points in the level.
    - There will also be certain special spawn points that continuously spawn enemies.
        - Or rather, these spawn points would spawn one at a time up to a max of N active enemies.

- Kitten-bat-icorn??

## TODO

- Make sure Claude accounts for whatever we'll need to do make our GDExtension work in web builds.

- EchoLocation:
    - Shader:
        - Bounce-back effect we talked about...
        - Stipples of the matching color as the echolocation should show more brightly than the others.
        - We should show stipples through water with echolocation, rather than attenuating with depth. Though, we should also still render the sharper surface/edges of water chunks.
    - Audio effect:
        - 
    - Damage:
        - Needs to be sharper cut-off.
        - Needs to not extend as far.
        - Needs to have lower damage at max cut-off distance.
- Collapsing:
    - Falling cells when detached
    - Falling liquid
    - Falling sand
- Enemies:
    - Coyote
    - Spider
    - Bird
- Test:
    - Falling cell, liquid, sand damage.
    - 
- Level generation:
    - 
- Music
- SFX

# Stretch

- Background art
- Polish player and enemy sprite shading.
- Polish level sprites.
- 
