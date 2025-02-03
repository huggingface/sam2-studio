//
//  SAM2+utils.swift
//  SAM2-Demo
//
//  Created by Martin Stachon on 16.01.2025.
//

import Foundation
import CoreML

func truncNormal(
    _ tensor: inout MLMultiArray,
    mean: Float = 0,
    std: Float = 1,
    a: Float = -2,
    b: Float = 2
) {
    // Helper function to compute standard normal cumulative distribution function
    func normCDF(_ x: Float) -> Float {
        return (1.0 + erf(x / sqrt(2.0))) / 2.0
    }

    // Check if mean is too far from [a, b]
    if (mean < a - 2 * std) || (mean > b + 2 * std) {
        print("Warning: mean is more than 2 std from [a, b] in truncNormalNoGrad. " +
              "The distribution of values may be incorrect.")
    }

    // Get upper and lower cdf values
    let l = normCDF((a - mean) / std)
    let u = normCDF((b - mean) / std)

    // Get total number of elements
    let count = tensor.count

    let scale = std * sqrt(2.0)

    for i in 0..<count {
        let uniformValue = Float.random(in: 2 * l - 1...2 * u - 1)
        let value = erfinv(uniformValue) * scale + mean
        let valueClamp = min(max(value, a), b)
        tensor[i] = NSNumber(value: valueClamp)
    }
}

// https://stackoverflow.com/questions/36784763/is-there-an-inverse-error-function-available-in-swifts-foundation-import
func erfinv(_ y: Float) -> Float {
    let center: Float = 0.7
    let a: [Float] = [ 0.886226899, -1.645349621,  0.914624893, -0.140543331]
    let b: [Float] = [-2.118377725,  1.442710462, -0.329097515,  0.012229801]
    let c: [Float] = [-1.970840454, -1.624906493,  3.429567803,  1.641345311]
    let d: [Float] = [ 3.543889200,  1.637067800]
    if abs(y) <= center {
        let z = pow(y,2)
        let num = (((a[3]*z + a[2])*z + a[1])*z) + a[0]
        let den = ((((b[3]*z + b[2])*z + b[1])*z + b[0])*z + 1.0)
        var x = y*num/den
        x = x - (erf(x) - y)/(2.0/sqrt(.pi)*exp(-x*x))
        x = x - (erf(x) - y)/(2.0/sqrt(.pi)*exp(-x*x))
        return x
    }
    else if abs(y) > center && abs(y) < 1.0 {
        let z = pow(-log((1.0-abs(y))/2),0.5)
        let num = ((c[3]*z + c[2])*z + c[1])*z + c[0]
        let den = (d[1]*z + d[0])*z + 1
        // should use the sign function instead of pow(pow(y,2),0.5)
        var x = y/pow(pow(y,2),0.5)*num/den
        x = x - (erf(x) - y)/(2.0/sqrt(.pi)*exp(-x*x))
        x = x - (erf(x) - y)/(2.0/sqrt(.pi)*exp(-x*x))
        return x
    } else if abs(y) == 1 {
        return y * Float(Int.max)
    } else {
        return .nan
    }
}

// Helper function for sign
func sign(_ x: Float) -> Float {
    return x < 0 ? -1 : 1
}
