# frozen_string_literal: true

require "test_helper"

class StudioStorefrontTest < ActiveSupport::TestCase
  setup do
    load(
      Rails.root.join(
        "db/seeds/lightek_pwa_storefront.rb"
      )
    )
  end

  test "Studio is owned by canonical storefront navigation" do
    studio =
      LightekPwa::Surface.find_by!(
        key: "studio"
      )

    navigation =
      LightekPwa::NavigationItem.find_by!(
        key: "studio"
      )

    assert_equal(
      "studio",
      studio.surface_type
    )

    assert_equal(
      "Studio",
      studio.label
    )

    assert_equal(
      "studio",
      navigation.surface_key
    )

    assert_equal(
      "#/studio",
      navigation.href
    )

    assert_equal(
      "primary",
      navigation.placement
    )

    assert_equal(
      "studio.pwa.bootstrap",
      navigation.requires_capability
    )
  end

  test "Money and Studio are absent from static shell navigation" do
    html =
      Rails.root
        .join(
          "public/lightek/index.html"
        )
        .read

    nav =
      html[
        /<nav id="primary-nav".*?<\/nav>/m
      ]

    assert_not_nil nav

    assert_not_includes(
      nav,
      "#/money"
    )

    assert_not_includes(
      nav,
      "#/studio"
    )
  end

  test "bootstrap exposes canonical Money and Studio navigation" do
    payload =
      LightekPwa::Bootstrap
        .new
        .call

    navigation =
      payload.fetch(
        :navigation
      )

    money =
      navigation.find do |item|
        item.fetch(
          :key
        ) == "money"
      end

    studio =
      navigation.find do |item|
        item.fetch(
          :key
        ) == "studio"
      end

    assert_not_nil money
    assert_not_nil studio

    assert_operator(
      money.fetch(
        :position
      ),
      :<,
      studio.fetch(
        :position
      )
    )

    assert_equal(
      "studio.pwa.bootstrap",
      studio.fetch(
        :requires_capability
      )
    )
  end
end
