//
//  ContentView.swift
//  LUT
//
//  Created by CodingGuru on 9/19/24.
//

import SwiftUI
import PhotosUI
import CoreImage

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var lutIntensity: Float = 1.0
    @State private var brightness: Float = 0.0
    @State private var contrast: Float = 1.0
    @State private var isShowingPhotoPicker = false
    @State private var selectedLUT: String = "SuperHR100" // Default LUT
    
    var lutFiles = ["SuperHR100", "AnotherLUT"] // List of LUT files
    
    var body: some View {
        VStack {
            if let selectedImage = selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 200)
            } else {
                Text("Pick an image")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            
            Button("Apply LUT") {
                if let selectedImage = selectedImage {
                    applyLUT(to: selectedImage, withLUT: selectedLUT, intensity: lutIntensity)
                }
            }
            .padding()
            
            if let processedImage = processedImage {
                Image(uiImage: processedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 200)
            }
//            Text("LUT Intensity")
            Slider(value: $lutIntensity, in: 0...1, step: 0.1) {
                Text("LUT Intensity")
            }
            .padding()
//            Text("Brightness")
            Slider(value: $brightness, in: -1...1, step: 0.1) {
                Text("Brightness")
            }
            .padding()
//            Text("Contrast")
            Slider(value: $contrast, in: 0.5...2, step: 0.1) {
                Text("Contrast")
            }
            .padding()
            
            Text("Choose LUT")
            Picker("Choose LUT", selection: $selectedLUT) {
                ForEach(lutFiles, id: \.self) { lut in
                    Text(lut)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            Button("Save to Photo Library") {
                if let processedImage = processedImage {
                    saveImageToPhotoLibrary(image: processedImage)
                }
            }
            .padding()
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            PhotoPicker(selectedImage: $selectedImage)
        }
        .onTapGesture {
            isShowingPhotoPicker = true
        }
    }
    
    func applyLUT(to image: UIImage, withLUT lutName: String, intensity: Float) {
        guard let lutURL = Bundle.main.url(forResource: lutName, withExtension: "cube") else {
            print("LUT file not found: \(lutName)")
            return
        }
        
        do {
            let lutData = try parseCubeFile(at: lutURL)
            if let processed = applyLUTFilter(image: image, lutData: lutData, intensity: intensity) {
                let adjustedImage = applyBrightnessAndContrast(to: processed)
                processedImage = adjustedImage
            }
        } catch {
            print("Failed to apply LUT: \(error)")
        }
    }
    
    func applyLUTFilter(image: UIImage, lutData: (cubeSize: Int, data: Data), intensity: Float) -> UIImage? {
        guard let inputImage = CIImage(image: image) else { return nil }
        
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(lutData.cubeSize, forKey: "inputCubeDimension")
        filter.setValue(lutData.data, forKey: "inputCubeData")
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        
        if let outputCIImage = filter.outputImage {
            let context = CIContext()
            if let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) {
                let lutAppliedImage = UIImage(cgImage: outputCGImage)
                return blendImages(original: image, filtered: lutAppliedImage, intensity: intensity)
            }
        }
        return nil
    }
    
    func applyBrightnessAndContrast(to image: UIImage) -> UIImage? {
        guard let inputCIImage = CIImage(image: image) else { return nil }
        
        let brightnessFilter = CIFilter(name: "CIColorControls")!
        brightnessFilter.setValue(inputCIImage, forKey: kCIInputImageKey)
        brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        brightnessFilter.setValue(contrast, forKey: kCIInputContrastKey)
        
        if let outputCIImage = brightnessFilter.outputImage {
            let context = CIContext()
            if let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) {
                return UIImage(cgImage: outputCGImage)
            }
        }
        return nil
    }
    
    func blendImages(original: UIImage, filtered: UIImage, intensity: Float) -> UIImage? {
        guard let originalCIImage = CIImage(image: original),
              let filteredCIImage = CIImage(image: filtered) else { return nil }
        
        let blendFilter = CIFilter(name: "CIBlendWithAlphaMask")!
        blendFilter.setValue(originalCIImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(filteredCIImage, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: CIColor(red: CGFloat(intensity), green: CGFloat(intensity), blue: CGFloat(intensity), alpha: 1.0)), forKey: kCIInputMaskImageKey)
        
        if let outputCIImage = blendFilter.outputImage {
            let context = CIContext()
            if let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) {
                return UIImage(cgImage: outputCGImage)
            }
        }
        return nil
    }
    
    func parseCubeFile(at url: URL) throws -> (cubeSize: Int, data: Data) {
        let content = try String(contentsOf: url)
        let lines = content.components(separatedBy: .newlines).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        
        var size = 0
        var cubeData: [Float] = []
        
        for line in lines {
            let values = line.split(separator: " ").compactMap { Float($0) }
            if values.count == 1 {
                size = Int(values[0])
            } else if values.count == 3 {
                cubeData.append(contentsOf: values)
            }
        }
        
        guard size > 0 else {
            throw NSError(domain: "Invalid cube size", code: 1, userInfo: nil)
        }
        
        let lutSize = size * size * size
        var lutArray: [Float] = Array(repeating: 0, count: lutSize * 4)
        
        for i in 0..<lutSize {
            lutArray[i * 4 + 0] = cubeData[i * 3 + 0]
            lutArray[i * 4 + 1] = cubeData[i * 3 + 1]
            lutArray[i * 4 + 2] = cubeData[i * 3 + 2]
            lutArray[i * 4 + 3] = 1.0 // Alpha channel
        }
        
        return (cubeSize: size, data: Data(buffer: UnsafeBufferPointer(start: lutArray, count: lutArray.count)))
    }
    
    func saveImageToPhotoLibrary(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        
        init(_ parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { (image, error) in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
