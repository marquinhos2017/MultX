import AVFoundation
import Flutter

class AudioEngineHandler {
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
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error.localizedDescription)")
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            case "pauseSounds":
    pause()
    result(nil)

// Adicione este método na classe AudioEngineHandler
func pause() {
    for player in players {
        player.pause()
    }
}



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
          let volumes = args["volumes"] as? [Double] else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "filePaths, pans ou volumes missing", details: nil))
        return
    }
    playSounds(paths: filePaths, pansFromFlutter: pans, volumesFromFlutter: volumes, result: result)

        case "stopSounds":
            stop()
            result(nil)
        case "setPlayerPan":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let pan = args["pan"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "index or pan missing", details: nil))
                return
            }
            setPan(index: index, pan: pan)
            result(nil)

            case "setAudioOutput":
    guard let output = call.arguments as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "output missing", details: nil))
        return
    }
    setAudioOutput(output: output)
    result(nil)
        case "setPlayerVolume":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "index or volume missing", details: nil))
                return
            }
            setVolume(index: index, volume: Float(volume))
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
            guard let path = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "path missing", details: nil))
                return
            }
            let duration = getDuration(for: path)
            result(duration)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

func playSounds(paths: [String], pansFromFlutter: [Double], volumesFromFlutter: [Double], result: FlutterResult) {
    stop()
    engine = AVAudioEngine()
    players = []
    audioFiles = []
    volumes = volumesFromFlutter.map { Float($0) }
    pans = pansFromFlutter.map { Float($0) }
    
    print("🔄 Iniciando carregamento dos arquivos...")

   for (index, path) in paths.enumerated() {
    let url = URL(fileURLWithPath: path)
    do {
        let file = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        players.append(player)
        audioFiles.append(file)
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

        // Aplicar pan/volume somente aqui
        player.pan = i < pans.count ? pans[i] : 0.0
        player.volume = i < volumes.count ? volumes[i] : 1.0

        player.scheduleFile(file, at: startTime)
    }

    for (i, player) in players.enumerated() {
        player.play(at: startTime)
    }

    durationInSeconds = audioFiles.map { Double($0.length) / $0.fileFormat.sampleRate }.max() ?? 0
    result(nil)

} catch {
    result(FlutterError(code: "ENGINE_ERROR", message: "Failed to start engine", details: error.localizedDescription))
}

}



    func stop() {
        for player in players {
            player.stop()
        }
        engine.stop()
    }

    func setVolume(index: Int, volume: Float) {
    guard index < players.count else { return }
    players[index].volume = volume
    if index < volumes.count {
        volumes[index] = volume
    }
}
func setAudioOutput(output: String) {
    let session = AVAudioSession.sharedInstance()
    
    do {
        switch output {
        case "headphones":
            try session.overrideOutputAudioPort(.none) // usa rota padrão, fones se conectados
            
        case "speaker":
            try session.overrideOutputAudioPort(.speaker) // força alto-falante
            
        case "bluetooth":
            // Não há método público para forçar bluetooth,
            // apenas permite a saída padrão que usa bluetooth se conectado
            try session.overrideOutputAudioPort(.none)
            
        default:
            try session.overrideOutputAudioPort(.none)
        }
    } catch {
        print("Erro ao configurar saída de áudio: \(error.localizedDescription)")
    }
}

func setPan(index: Int, pan: Double) {
    guard index < players.count else { return }
    players[index].pan = Float(pan)
    if index < pans.count {
        pans[index] = Float(pan)
    }
}


    func mutePlayer(index: Int, mute: Bool) {
        guard index < players.count else { return }
        players[index].volume = mute ? 0 : 1
    }
func seek(to seconds: Double) {
    print("⏪ Seeking to \(seconds) segundos")

    guard !players.isEmpty, !audioFiles.isEmpty else {
        print("⚠️ Nenhum player ou arquivo disponível para seek")
        return
    }

    // Parar todos os players
    for player in players {
        player.stop()
    }

    guard let renderTime = engine.outputNode.lastRenderTime else {
        print("❌ Falha ao obter renderTime no seek")
        return
    }

    // Tempo comum de início
    let hostTime = renderTime.hostTime + UInt64(0.02 * Double(NSEC_PER_SEC))
    let startTime = AVAudioTime(hostTime: hostTime)

    print("⏱️ Agendando players para hostTime: \(hostTime)")

    for (i, player) in players.enumerated() {
        guard i < audioFiles.count else { continue }
        let file = audioFiles[i]
        let sampleRate = file.fileFormat.sampleRate
        let frameOffset = AVAudioFramePosition(seconds * sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, file.length - frameOffset))

        guard frameOffset < file.length else {
            print("⚠️ Posição de seek fora do limite no player \(i)")
            continue
        }

        player.scheduleSegment(
            file,
            startingFrame: frameOffset,
            frameCount: remainingFrames,
            at: startTime,
            completionHandler: {
                print("🏁 Player \(i) terminou após seek.")
            }
        )
        print("🎯 Player \(i) agendado com offset: \(frameOffset), frames restantes: \(remainingFrames)")
    }

    for (i, player) in players.enumerated() {
        player.play(at: startTime)
        print("▶️ Player \(i) play() chamado com sincronização.")
    }
}






    func getDuration(for path: String) -> Double {
        let url = URL(fileURLWithPath: path)
        do {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.fileFormat.sampleRate
        } catch {
            return 0
        }
    }

func removePlayer(index: Int) {
    // Verifica se o índice é válido
    guard players.indices.contains(index) else {
        print("❌ Índice inválido para remoção: \(index)")
        return
    }
    
    print("🗑️ Removendo player no índice \(index)")
    
    // Pausa o player específico
    let playerToRemove = players[index]
    playerToRemove.stop()
    engine.detach(playerToRemove)
    
    // Remove das listas
    players.remove(at: index)
    audioFiles.remove(at: index)
    
    // Se não houver mais players, para o engine
    if players.isEmpty {
        engine.stop()
        print("🛑 Todos os players removidos - engine parado")
        return
    }
    
    // Reconecta todos os players restantes
    do {
        // Para cada player restante
        for (i, player) in players.enumerated() {
            let file = audioFiles[i]
            
            // Obtém a posição atual de reprodução
            if let nodeTime = player.lastRenderTime,
               let playerTime = player.playerTime(forNodeTime: nodeTime) {
                let currentPosition = Double(playerTime.sampleTime) / playerTime.sampleRate
                
                print("🔄 Reagendando player \(i) na posição: \(currentPosition) segundos")
                
                let frameOffset = AVAudioFramePosition(currentPosition * file.fileFormat.sampleRate)
                let remainingFrames = AVAudioFrameCount(file.length - frameOffset)
                
                if frameOffset < file.length {
                    player.scheduleSegment(file,
                                        startingFrame: frameOffset,
                                        frameCount: remainingFrames,
                                        at: nil,
                                        completionHandler: nil)
                }
            }
        }
        
        // Reinicia a reprodução
        for player in players {
            player.play()
        }
        
        print("✅ Players restantes reconectados e reprodução continuada")
    } catch {
        print("❌ Erro ao reconectar players: \(error.localizedDescription)")
    }
}}
