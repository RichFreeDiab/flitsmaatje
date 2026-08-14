HStack {
    Text(direction.arrow)
    if let exit = direction.exitInfo, direction.distance < 2000 {
        Text(exit.number.isEmpty ? exit.name : "Afrit \(exit.number)")
            .font(.caption)
            .foregroundColor(.orange)
    }
}