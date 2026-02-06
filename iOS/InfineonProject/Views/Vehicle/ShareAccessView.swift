//
//  ShareAccessView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/2/26.
//

import AaronUI
import CoreImage.CIFilterBuiltins
import SwiftUI

struct GradientColors {
  let softLavender: Color
  let paleSkyBlue: Color
  let mintGreen: Color
  let dustyRose: Color
  let peachCream: Color
  let babyBlue: Color
  let lilacMist: Color
  let seafoamPastel: Color
  let blushPink: Color

  static let light = GradientColors(
    softLavender: Color(red: 220 / 255, green: 208 / 255, blue: 255 / 255),
    paleSkyBlue: Color(red: 176 / 255, green: 218 / 255, blue: 255 / 255),
    mintGreen: Color(red: 198 / 255, green: 255 / 255, blue: 226 / 255),
    dustyRose: Color(red: 255 / 255, green: 198 / 255, blue: 218 / 255),
    peachCream: Color(red: 255 / 255, green: 224 / 255, blue: 196 / 255),
    babyBlue: Color(red: 198 / 255, green: 222 / 255, blue: 255 / 255),
    lilacMist: Color(red: 232 / 255, green: 208 / 255, blue: 238 / 255),
    seafoamPastel: Color(red: 202 / 255, green: 255 / 255, blue: 242 / 255),
    blushPink: Color(red: 255 / 255, green: 218 / 255, blue: 233 / 255)
  )

  static let dark = GradientColors(
    softLavender: Color(red: 100 / 255, green: 88 / 255, blue: 135 / 255),
    paleSkyBlue: Color(red: 76 / 255, green: 118 / 255, blue: 155 / 255),
    mintGreen: Color(red: 78 / 255, green: 135 / 255, blue: 106 / 255),
    dustyRose: Color(red: 135 / 255, green: 78 / 255, blue: 98 / 255),
    peachCream: Color(red: 135 / 255, green: 104 / 255, blue: 76 / 255),
    babyBlue: Color(red: 78 / 255, green: 102 / 255, blue: 135 / 255),
    lilacMist: Color(red: 112 / 255, green: 88 / 255, blue: 118 / 255),
    seafoamPastel: Color(red: 82 / 255, green: 135 / 255, blue: 122 / 255),
    blushPink: Color(red: 135 / 255, green: 98 / 255, blue: 113 / 255)
  )
}

struct ShareAccessView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  let vehicle: Vehicle

  @State private var isActive = false
  @State private var showCode = false
  @State private var qrCodeImage: UIImage = .init()

  let context = CIContext()
  let filter = CIFilter.qrCodeGenerator()

  private var colors: GradientColors {
    colorScheme == .dark ? .dark : .light
  }

  private func generateQRCode(from string: String) {
    let data = Data(string.utf8)
    filter.setValue(data, forKey: "inputMessage")

    if let qrCode = filter.outputImage {
      let transform = CGAffineTransform(scaleX: 10, y: 10)
      let scaledQrCode = qrCode.transformed(by: transform)

      if let cgImage = context.createCGImage(
        scaledQrCode,
        from: scaledQrCode.extent
      ) {
        qrCodeImage = UIImage(cgImage: cgImage)
      }
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TimelineView(.animation) { context in
          let s = context.date.timeIntervalSince1970
          let v = Float(sin(s)) / 4

          MeshGradient(
            width: 3,
            height: 3,
            points: [
              [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
              [0.0, 0.5], [0.5 + v, 0.5 - v], [1.0, 0.3 - v],
              [0.0, 1.0], [0.7 - v, 1.0], [1.0, 1.0],
            ],
            colors: [
              colors.softLavender, colors.paleSkyBlue,
              isActive ? colors.blushPink : colors.mintGreen,
              colors.dustyRose, colors.peachCream, colors.babyBlue,
              isActive ? colors.peachCream : colors.lilacMist,
              colors.seafoamPastel, colors.blushPink,
            ]
          )
        }
        .ignoresSafeArea()

        VStack {
          Image(uiImage: qrCodeImage)
            .interpolation(.none)
            .resizable()
            .aspectRatio(1, contentMode: .fit)

          Spacer()

          Button {
            Haptics.impact()

            withAnimation(.bouncy) {
              showCode.toggle()
            }
          } label: {
            HStack {
              Image(systemName: showCode ? "eye.slash.fill" : "eye.fill")
                .contentTransition(.symbolEffect(.automatic))

              Text("\(showCode ? "Hide" : "Show") code")
                .contentTransition(.numericText(value: 0))
            }
          }
          .padding(.bottom)

          Text(showCode ? vehicle.inviteCode : "XXXXXX")
            .contentTransition(.numericText(value: 0))
            .blur(radius: showCode ? 0 : 10)
            .transition(.blurReplace)
            .font(.title)
            .fontDesign(.monospaced)
            .foregroundStyle(.white)
            .padding()
            .background(.gray)
            .clipShape(.rect(cornerRadius: 10))

          Spacer()
        }
      }
      .navigationTitle("Share Access")
      .onAppear {
        generateQRCode(from: "infineon://add-vehicle/\(vehicle.inviteCode)")

        withAnimation(
          .easeInOut(duration: 3).repeatForever(autoreverses: true)
        ) {
          isActive = true
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview {
  Text("Sheet is open")
    .sheet(isPresented: .constant(true)) {
      ShareAccessView(
        vehicle: Vehicle(
          id: "test",
          createdAt: .now,
          updatedAt: .now,
          name: "Test Vehicle",
          description: nil,
          inviteCode: "ABC123",
          ownerId: nil
        ))
    }
}
