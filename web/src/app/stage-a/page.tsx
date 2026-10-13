export default function StageAPage() {
  return (
    <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
      <h2 className="text-xl font-bold text-gray-900 mb-2">Stage A: 단방향 메시지 (Web → Host)</h2>
      <p className="text-gray-600 mb-6 text-sm">
        Web에서 발생한 입력을 Host로 전달하는 가장 단순한 형태의 단방향 통신입니다.
      </p>
      <div className="bg-gray-50 border border-dashed border-gray-300 rounded-lg p-6 text-center text-gray-500">
        Stage A 구현 준비 완료 (대기 중: Issue #8)
      </div>
    </div>
  );
}
