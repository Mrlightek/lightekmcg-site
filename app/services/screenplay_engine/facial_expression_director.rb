module ScreenplayEngine
  class FacialExpressionDirector
    # Mapping emotional states to ARKit blendshape keys
    ARKIT_EXPRESSIONS = {
      frantic: {
        eyeWideLeft: 0.8,
        eyeWideRight: 0.8,
        browInnerUp: 0.9,
        browOuterUpLeft: 0.4,
        browOuterUpRight: 0.4,
        jawOpen: 0.3,
        mouthFunnel: 0.2
      },
      desperate: {
        browInnerUp: 1.0,
        browDownLeft: 0.6,
        browDownRight: 0.6,
        mouthPucker: 0.4,
        mouthFrownLeft: 0.7,
        mouthFrownRight: 0.7
      },
      grief: {
        eyeBlinkLeft: 0.3,
        eyeBlinkRight: 0.3,
        browInnerUp: 1.0,
        mouthFrownLeft: 0.9,
        mouthFrownRight: 0.9,
        jawPuff: 0.0
      },
      hopeful: {
        eyeWideLeft: 0.3,
        eyeWideRight: 0.3,
        browInnerUp: 0.2,
        mouthSmileLeft: 0.6,
        mouthSmileRight: 0.6
      }
    }.freeze

    def self.generate_expression_keys(emotion, start_frame, duration_frames = 48)
      shapes = ARKIT_EXPRESSIONS[emotion] || {}
      
      {
        start_frame: start_frame,
        peak_frame: start_frame + (duration_frames * 0.3).round, # Fast transition to emotion
        end_frame: start_frame + duration_frames,
        blendshapes: shapes
      }
    end
  end
end