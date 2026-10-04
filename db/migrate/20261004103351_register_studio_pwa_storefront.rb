# frozen_string_literal: true

class RegisterStudioPwaStorefront < ActiveRecord::Migration[8.0]
  def up
    money_surface =
      LightekPwa::Surface.find_by(
        key: "money"
      )

    surface_attributes = {
      surface_type: "studio",
      label: "Studio",
      position: 70,
      enabled: true,
      configuration: {
        "title" =>
          "Lightek Studio",

        "description" =>
          "The creation operating system for Lightek."
      }
    }

    if money_surface
      surface_attributes[
        :seed_namespace
      ] =
        money_surface.seed_namespace

      surface_attributes[
        :seed_version
      ] =
        money_surface.seed_version
    end

    studio =
      LightekPwa::Surface
        .find_or_initialize_by(
          key: "studio"
        )

    studio.assign_attributes(
      surface_attributes
    )

    studio.save!

    money_navigation =
      LightekPwa::NavigationItem.find_by(
        key: "money"
      )

    navigation_attributes = {
      label: "Studio",
      surface_key: "studio",
      href: "#/studio",
      placement: "primary",
      position: 57,
      enabled: true,
      requires_capability:
        "studio.pwa.bootstrap",
      configuration: {}
    }

    if money_navigation
      navigation_attributes[
        :seed_namespace
      ] =
        money_navigation.seed_namespace

      navigation_attributes[
        :seed_version
      ] =
        money_navigation.seed_version
    end

    navigation =
      LightekPwa::NavigationItem
        .find_or_initialize_by(
          key: "studio"
        )

    navigation.assign_attributes(
      navigation_attributes
    )

    navigation.save!
  end

  def down
    LightekPwa::NavigationItem
      .where(
        key: "studio"
      )
      .delete_all

    LightekPwa::Surface
      .where(
        key: "studio"
      )
      .destroy_all
  end
end
