require "zip"

module LightekConnect
  class WordpressPackage
    # Read only release-owned files. Shared assets are authoritative, including
    # before the CLI packager has refreshed the plugin's checked-in copies.
    FILES = {
      "lightek-connect.php" => "integrations/wordpress/lightek-connect/lightek-connect.php",
      "readme.txt" => "integrations/wordpress/lightek-connect/readme.txt",
      "uninstall.php" => "integrations/wordpress/lightek-connect/uninstall.php",
      "assets/workspace.js" => "public/lightek-connect/workspace.js",
      "assets/workspace.css" => "public/lightek-connect/workspace.css"
    }.freeze

    def self.build
      Zip::OutputStream.write_buffer do |archive|
        FILES.each do |name, path|
          archive.put_next_entry("lightek-connect/#{name}")
          archive.write(File.binread(Rails.root.join(path)))
        end
      end.string
    end
  end
end
