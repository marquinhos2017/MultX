import AVFoundation
import Flutter

class AudioEngineHandler {
    var pitchUnits: [AVAudioUnitTimePitch] = []

    var engine = AVAudioEngine()
    var players: [AVAudioPlayerNode] = []
    var audioFiles: [AVAudioFile] = []
    var durationInSeconds: Double = 0
    var volumes: [Float] = []
    var pans: [Float] = []

    init() {
        configureAudioSession()
    }

   private func configureAudioSession() {
    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, 
                               mode: .default, 
                               options: [.mixWithOthers, .allowAirPlay, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        print("✅ Sessão de áudio configurada com sucesso")
    } catch {
        print("❌ AVAudioSession error: \(error.localizedDescription)")
    }
}

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pauseSounds":
            pause()
            result(nil)
            
        case "stopSounds":
            stop()
            result(nil)
            
        case "resumeSounds":
            resume()
            result(nil)

             case "setPitch":  // ADD THIS CASE
        guard let args = call.arguments as? [String: Any],
              let index = args["index"] as? Int,
              let pitch = args["pitch"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "index or pitch missing", details: nil))
            return
        }
        setPitch(index: index, pitch: Float(pitch))
        result(nil)
            
        case "removePlayer":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "index missing", details: nil))
                return
            }
            removePlayer(index: index)
            result(nil)
            
       case "playUploadedSounds":
    guard let args = call.arguments as? [String: Any],
          let filePaths = args["filePaths"] as? [String],
          let pans = args["pans"] as? [Double],
          let volumes = args["volumes"] as? [Double],
          let pitchValues = args["pitchValues"] as? [Double],
          let startPosition = args["startPosition"] as? Double else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
        return
    }
    playSounds(paths: filePaths, 
               pansFromFlutter: pans, 
               volumesFromFlutter: volumes, 
               pitchValuesFromFlutter: pitchValues, // Passe os pitch values
               startPosition: startPosition, 
               result: result)
            
        case "setPlayerPan":
    guard let args = call.arguments as? [String: Any],
          let index = args["index"] as? Int,
          let pan = args["pan"] as? Double else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "index or pan missing", details: nil))
        return
    }
    setPan(index: index, pan: pan)
    result(nil)


        case "setPlayerVolume":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "index or volume missing", details: nil))
                return
            }
            setVolume(index: index, volume: volume)
            result(nil)
            
        case "mutePlayer":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let mute = args["mute"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "index or mute missing", details: nil))
                return
            }
            mutePlayer(index: index, mute: mute)
            result(nil)
            
        case "seekToPosition":
            guard let args = call.arguments as? [String: Any],
                  let seconds = args["seconds"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "seconds missing", details: nil))
                return
            }
            seek(to: seconds)
            result(nil)
            
      case "getAudioDuration":
    guard let args = call.arguments as? [String: Any],
          let path = args["filePath"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "filePath missing", details: nil))
        return
    }
    result(getDuration(for: path))
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Audio Playback Methods

func playSounds(paths: [String], 
                pansFromFlutter: [Double], 
                volumesFromFlutter: [Double], 
                pitchValuesFromFlutter: [Double],
                startPosition: Double, 
                result: FlutterResult) {
    stop()
    engine = AVAudioEngine()
    players = []
    audioFiles = []
    pitchUnits = []
    self.volumes = volumesFromFlutter.map { Float($0) }
    self.pans = pansFromFlutter.map { Float($0) }
    
    print("🔄 Loading files from \(startPosition) seconds...")
    
    for (index, path) in paths.enumerated() {
        let url = URL(fileURLWithPath: path)
        do {
            let file = try AVAudioFile(forReading: url)
            let player = AVAudioPlayerNode()
            let pitchUnit = AVAudioUnitTimePitch()
            
            // Aplique o pitch value correspondente (se disponível)
            let pitchValue = index < pitchValuesFromFlutter.count ? 
                Float(pitchValuesFromFlutter[index]) : 0.0
            pitchUnit.pitch = pitchValue

            engine.attach(player)
            engine.attach(pitchUnit)
            
            engine.connect(player, to: pitchUnit, format: file.processingFormat)
            engine.connect(pitchUnit, to: engine.mainMixerNode, format: file.processingFormat)
            
            players.append(player)
            audioFiles.append(file)
            pitchUnits.append(pitchUnit)
        } catch {
            result(FlutterError(code: "AUDIO_ERROR", message: "Failed to load audio", details: error.localizedDescription))
            return
        }
    }
        
        do {
            try engine.start()
            guard let renderTime = engine.outputNode.lastRenderTime else {
                result(FlutterError(code: "TIME_ERROR", message: "Failed to get render time", details: nil))
                return
            }
            let hostTime = renderTime.hostTime + UInt64(0.02 * Double(NSEC_PER_SEC))
            let startTime = AVAudioTime(hostTime: hostTime)
            
            for (i, player) in players.enumerated() {
                let file = audioFiles[i]
                let sampleRate = file.fileFormat.sampleRate
                let frameOffset = AVAudioFramePosition(startPosition * sampleRate)
                let remainingFrames = AVAudioFrameCount(max(0, file.length - frameOffset))
                
                if frameOffset < file.length {
                    player.pan = i < pans.count ? pans[i] : 0.0
                    player.volume = i < volumes.count ? volumes[i] : 1.0
                    player.scheduleSegment(file, startingFrame: frameOffset, frameCount: remainingFrames, at: startTime, completionHandler: nil)
                }
            }
            
            players.forEach { $0.play(at: startTime) }
            durationInSeconds = audioFiles.map { Double($0.length) / $0.fileFormat.sampleRate }.max() ?? 0
            result(nil)
            
        } catch {
            result(FlutterError(code: "ENGINE_ERROR", message: "Failed to start engine", details: error.localizedDescription))
        }
    }

func setPitch(index: Int, pitch: Float) {
    guard index < pitchUnits.count else { return }
    pitchUnits[index].pitch = pitch // valor em centavos (-2400 a 2400, onde 100 cent = 1 semitom)
}


 func resume() {
    if !engine.isRunning {
        do { 
            try engine.start() 
            // Reaplicar os pitches após reiniciar o engine
            for (index, pitchUnit) in pitchUnits.enumerated() {
                // Mantenha os valores de pitch atuais
                // (Se você quiser manter os últimos valores aplicados)
            }
        } catch { 
            print("❌ Erro ao reiniciar engine: \(error.localizedDescription)"); 
            return 
        }
    }
    for player in players where !player.isPlaying { 
        player.play() 
    }
}

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
        players.removeAll()
        audioFiles.removeAll()
        volumes.removeAll()
        pans.removeAll()
    }

    func pause() {
        for player in players where player.isPlaying { player.pause() }
    }

    

    func setVolume(index: Int, volume: Double) {
        guard index < players.count else { return }
        let floatVolume = Float(volume)
        players[index].volume = floatVolume
        if index < volumes.count { volumes[index] = floatVolume }
    }

    func setPan(index: Int, pan: Double) {
        guard index < players.count else { return }
        let floatPan = Float(pan)
        players[index].pan = floatPan
        if index < pans.count { pans[index] = floatPan }
    }

    func mutePlayer(index: Int, mute: Bool) {
        guard index < players.count else { return }
        players[index].volume = mute ? 0 : 1
    }

    func seek(to seconds: Double) {
        guard !players.isEmpty, !audioFiles.isEmpty else { return }
        let wasPlaying = players.first?.isPlaying ?? false
        players.forEach { $0.stop() }
        
        guard let renderTime = engine.outputNode.lastRenderTime else { return }
        let hostTime = renderTime.hostTime + UInt64(0.02 * Double(NSEC_PER_SEC))
        let startTime = AVAudioTime(hostTime: hostTime)
        
        for (i, player) in players.enumerated() {
            guard i < audioFiles.count else { continue }
            let file = audioFiles[i]
            let frameOffset = AVAudioFramePosition(seconds * file.fileFormat.sampleRate)
            let remainingFrames = AVAudioFrameCount(max(0, file.length - frameOffset))
            guard frameOffset < file.length else { continue }
            player.scheduleSegment(file, startingFrame: frameOffset, frameCount: remainingFrames, at: startTime, completionHandler: nil)
        }
        
        if wasPlaying { players.forEach { $0.play(at: startTime) } }
    }

  func getDuration(for path: String) -> Double {
    let url = URL(fileURLWithPath: path)
    do {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        let durationInSeconds = CMTimeGetSeconds(duration)
        return durationInSeconds.isNaN ? 0 : durationInSeconds
    } catch {
        print("Erro ao obter duração: \(error.localizedDescription)")
        return 0
    }
}

    func removePlayer(index: Int) {
        guard players.indices.contains(index) else { return }
        let playerToRemove = players[index]
        playerToRemove.stop()
        engine.detach(playerToRemove)
        players.remove(at: index)
        audioFiles.remove(at: index)
        
        if players.isEmpty { engine.stop(); return }
        
        for (i, player) in players.enumerated() {
            let file = audioFiles[i]
            if let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) {
                let currentPosition = Double(playerTime.sampleTime) / playerTime.sampleRate
                let frameOffset = AVAudioFramePosition(currentPosition * file.fileFormat.sampleRate)
                let remainingFrames = AVAudioFrameCount(file.length - frameOffset)
                if frameOffset < file.length {
                    player.scheduleSegment(file, startingFrame: frameOffset, frameCount: remainingFrames, at: nil, completionHandler: nil)
                }
            }
        }
        players.forEach { $0.play() }
    }

    func setAudioOutput(output: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            switch output {
            case "headphones": try session.overrideOutputAudioPort(.none)
            case "speaker": try session.overrideOutputAudioPort(.speaker)
            case "bluetooth": try session.overrideOutputAudioPort(.none)
            default: try session.overrideOutputAudioPort(.none)
            }
        } catch {
            print("Erro ao configurar saída de áudio: \(error.localizedDescription)")
        }
    }
}
