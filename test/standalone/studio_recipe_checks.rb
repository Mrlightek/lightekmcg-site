require_relative "../support/studio_recipe_fixture"
require "tmpdir"
require_relative "../../app/services/studio/media_process"
require_relative "../../app/services/studio/recipe"

def assert(condition, message)
  raise message unless condition
end

def rejects(expected)
  yield
  raise "Expected an error: #{expected}"
rescue ArgumentError => error
  assert(error.message == expected, error.message)
end

def run(executable, *args)
  Studio::MediaProcess.run!([executable, *args])
end

photo = File.expand_path(ENV.fetch("PHOTOCRAFT_CLI"))
motion = File.expand_path(ENV.fetch("EFFECTCRAFT_CLI"))
character = StudioRecipeFixture.path
definitions = File.expand_path("../../config/studio/recipes", __dir__)

Dir.mktmpdir("studio-recipe-") do |output|
  photo_recipe = Studio::Recipe.load(File.join(definitions, "add_facial_hair.json"))
  assert(Studio::Recipe.new(JSON.parse(photo_recipe.to_json)).commands == photo_recipe.commands, "Recipe round trip failed")
  rejects("Invalid parameter: density") { photo_recipe.commands("density" => 1.2) }

  missing_ref = JSON.parse(photo_recipe.to_json)
  missing_ref.fetch("steps").fetch(1)["params"]["layer"] = {"$ref" => "missing"}
  rejects("Unresolved $ref: missing") { Studio::Recipe.new(missing_ref) }
  forward_ref = JSON.parse(photo_recipe.to_json)
  forward_ref.fetch("steps").fetch(1)["params"]["layer"] = {"$ref" => "hair_layer"}
  rejects("Unresolved $ref: hair_layer") { Studio::Recipe.new(forward_ref) }
  duplicate_ref = JSON.parse(photo_recipe.to_json)
  duplicate_ref.fetch("steps").fetch(2)["returns"] = {"hair_group" => ["layer"]}
  rejects("Duplicate return handle: hair_group") { Studio::Recipe.new(duplicate_ref) }
  unknown_input = JSON.parse(photo_recipe.to_json)
  unknown_input.delete("inputs")
  rejects("Unresolved $input: mask_path") { Studio::Recipe.new(unknown_input) }

  required = JSON.parse(photo_recipe.to_json)
  required.fetch("inputs").fetch("mask_path").delete("default")
  rejects("Unresolved $input: mask_path") { Studio::Recipe.new(required).commands }
  rejects("Invalid input: mask_path") { photo_recipe.commands(inputs: {"mask_path" => "/tmp/mask.png"}) }

  missing_result = JSON.parse(photo_recipe.to_json)
  missing_result.fetch("steps").first["returns"] = {"hair_group" => ["not_returned"]}
  failed = File.join(output, "unresolved.pcraft")
  rejects("Unresolved return handle hair_group from layer.new.group") do
    Studio::Recipe.new(missing_result).run!(executable: photo, input: character, output: failed)
  end
  assert(!File.exist?(failed), "A missing return handle published a partial project")

  actual = File.join(output, "recipe.pcraft")
  manual = File.join(output, "manual.pcraft")
  mask = [[97, 155], [115, 197], [140, 211], [190, 211], [225, 173], [220, 233], [193, 260], [161, 270], [127, 255], [104, 226]]
  photo_params = {"position" => [3, 1], "scale" => 93, "rotation" => 7, "color" => "#433039", "density" => 0.78}
  Studio::Recipe.new(required).run!(executable: photo, input: character, output: actual,
    parameters: photo_params, inputs: {"mask_path" => mask})

  # Independently transcribed manual CLI sequence with literal user settings.
  run(photo, "run", character, "--no-gpu",
    "--cmd", "layer.new.group", "--params", '{"name":"Facial Hair"}',
    "--cmd", "layer.new.layer", "--params", '{"name":"Tint and texture"}',
    "--cmd", "edit.fill", "--params", '{"contents":"color","color":"#433039","target":"pixels"}',
    "--cmd", "filter.noise.addNoise", "--params", '{"amount":65,"distribution":"gaussian","monochromatic":true,"seed":77}',
    "--cmd", "filter.blur.motionBlur", "--params", '{"angle":78,"distance":7}',
    "--cmd", "select.lasso", "--params", '{"points":[[97,155],[115,197],[140,211],[190,211],[225,173],[220,233],[193,260],[161,270],[127,255],[104,226]],"polygonal":true}',
    "--cmd", "select.modify.feather", "--params", '{"radius":4}',
    "--cmd", "layer.layerMask.revealSelection",
    "--cmd", "select.deselect",
    "--cmd", "edit.transform", "--params", '{"scaleX":93,"scaleY":93,"rotate":7,"dx":3,"dy":1,"reference":[160,215]}',
    "--cmd", "layer.setProps", "--params", '{"opacity":0.78}', "--out", manual)

  actual_png = File.join(output, "recipe.png")
  manual_png = File.join(output, "manual.png")
  run(photo, "run", actual, "--no-gpu", "--out", actual_png)
  run(photo, "run", manual, "--no-gpu", "--out", manual_png)
  assert(File.binread(actual_png) == File.binread(manual_png), "Photo PNG differs from manual output")
  info = JSON.parse(run(photo, "info", actual))
  group, background = info.fetch("layers")
  beard = group.fetch("children").fetch(0)
  assert(group["name"] == "Facial Hair" && group["kind"] == "Group", "Editable group missing")
  assert(beard["hasMask"] && (beard["opacity"] - 0.78).abs < 0.0001, "Mask or density missing")
  assert(background["name"] == "Background" && background["visible"], "Source layer missing")
  hidden = File.join(output, "hidden.png")
  run(photo, "run", actual, "--no-gpu", "--cmd", "layer.select", "--params", '{"name":"Facial Hair"}',
    "--cmd", "layer.setProps", "--params", '{"visible":false}', "--out", hidden)
  source_png = File.join(output, "source.png")
  run(photo, "run", character, "--no-gpu", "--out", source_png)
  assert(File.binread(hidden) == File.binread(source_png), "Source pixels changed underneath the effect")
  assert(File.binread(actual_png) != File.binread(hidden), "Effect had no visible impact")
  shifted = File.join(output, "shifted.png")
  photo_recipe.run!(executable: photo, input: character, output: shifted, parameters: photo_params,
    inputs: {"mask_path" => mask.map { |x, y| [x + 20, y] }})
  assert(File.binread(shifted) != File.binread(actual_png), "Runtime mask did not change the pixels")
  puts "PASS PhotoCraft: bound group and layer IDs, caller mask, byte-for-byte manual PNG match, original pixels preserved"

  motion_recipe = Studio::Recipe.load(File.join(definitions, "animate_layer_position.json"))
  actual_project = File.join(output, "recipe.ecproj")
  manual_project = File.join(output, "manual.ecproj")
  motion_recipe.run!(executable: motion, output: actual_project,
    parameters: {"start_position" => [52, 90], "end_position" => [252, 90], "end_time" => 2},
    inputs: {"layer_name" => "Runtime Tile"})
  run(motion, "run", "comp.new", '{"name":"Recipe Motion","width":320,"height":180,"frameRate":24,"duration":3}',
    "layer.newSolid", '{"name":"Runtime Tile","width":30,"height":30,"color":"#febb33"}',
    "--empty", "--save-as", manual_project)
  run(motion, "set", "Recipe Motion", "Runtime Tile", "transform/position", "[52,90]", manual_project, "--save")
  run(motion, "exec", "prop.toggleAnimation", "--params", '{"layer":"Runtime Tile","path":"transform/position"}',
    manual_project, "--save")
  run(motion, "set", "Recipe Motion", "Runtime Tile", "transform/position", "[252,90]", "--time", "2", manual_project, "--save")

  {"0" => 52.0, "1" => 152.0, "2" => 252.0}.each do |time, x|
    args = ["get", "Recipe Motion", "Runtime Tile", "transform/position"]
    result = JSON.parse(run(motion, *args, actual_project, "--time", time, "--json"))
    manual_result = JSON.parse(run(motion, *args, manual_project, "--time", time, "--json"))
    assert(result.fetch("keys").size == 2 && result.fetch("value") == [x, 90.0, 0.0], "Wrong motion at #{time}s")
    assert(result == manual_result, "Keyframe state differs from manual execution at #{time}s")
    frames = [actual_project, manual_project].each_with_index.map do |project, index|
      frame = File.join(output, "motion-#{index}-#{time}.png")
      run(motion, "render-frame", "--comp", "Recipe Motion", "--time", time, "--out", frame, project)
      File.binread(frame)
    end
    assert(frames.uniq.size == 1, "Rendered frame differs from manual execution at #{time}s")
  end
  puts "PASS EffectCraft: bound layer ID, caller layer name, byte-for-byte manual CPU frames at 0s, 1s and 2s"
end
