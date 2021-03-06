require_relative '../common'
require_relative '../helpers/quizzes_common'

describe 'taking a quiz' do
  include_context 'in-process server selenium tests'
  include QuizzesCommon

  context 'as a student' do
    before(:once) do
      course_with_teacher(active_all: 1)
      course_with_student(course: @course, active_all: 1)
    end

    before(:each) { user_session(@student) }

    context 'when the quiz has an access code' do
      let(:access_code) { '1234' }
      let(:quiz) do
        @context = @course
        quiz = quiz_model
        2.times { quiz.quiz_questions.create! question_data: true_false_question_data }
        quiz.access_code = access_code
        quiz.generate_quiz_data
        quiz.save!
        quiz.reload
      end

      context 'when the quiz has "One Question at a Time" enabled' do
        let(:oqaat_quiz) do
          @context = @course
          quiz = quiz_model
          2.times { quiz.quiz_questions.create! question_data: true_false_question_data }
          quiz.access_code = access_code
          quiz.title = 'OQAAT quiz'
          quiz.one_question_at_a_time = true
          quiz.generate_quiz_data
          quiz.save!
          quiz.reload
        end

        def verify_no_access_code_reprompts_during_oqaat_quiz
          take_and_answer_quiz(
            submit: false,
            access_code: access_code,
            quiz: oqaat_quiz
          )

          yield if block_given?

          # select second question
          select_question_from_column_links(@quiz.quiz_questions[1].id)
          verify_no_access_code_prompt

          # answer second question
          answer_question(@quiz.stored_questions[1][:answers][0][:id])

          submit_quiz

          verify_no_access_code_prompt
        end

        def verify_no_access_code_prompt
          expect(f('#quiz_access_code')).to be_falsey
        end

        it 'only asks once for the access code', priority: "1", test_id: 522898 do
          verify_no_access_code_reprompts_during_oqaat_quiz
        end

        context 'when the access code changes during an active quiz session' do

          it 'doesn\'t prompt for the access code again', priority: "1", test_id: 522902 do
            skip('Known issue: CNVS-23169')
            verify_no_access_code_reprompts_during_oqaat_quiz do
              # change the access code
              oqaat_quiz.access_code = access_code.reverse!
              oqaat_quiz.save!
              oqaat_quiz.reload
            end
          end
        end
      end

      context 'when the quiz has unlimited attempts' do
        let(:quiz_with_unlimited_attempts) do
          quiz.allowed_attempts = -1
          quiz.save!
          quiz.reload
        end

        def start_and_exit_quiz
          take_and_answer_quiz(
            submit: false,
            access_code: access_code,
            quiz: quiz_with_unlimited_attempts
          )

          # exit quiz without submitting
          expect_new_page_load do
            fln('Quizzes').click
            driver.switch_to.alert.accept
          end

          yield if block_given?

        ensure
          # This prevents selenium from freezing when the dialog appears upon leaving the quiz
          fln('Quizzes').click
          driver.switch_to.alert.accept
        end

        def verify_access_code_prompt
          expect(f('#quiz_access_code')).to be_truthy
        end

        it 'prompts for access code upon resuming the quiz', priority: "1", test_id: 421218 do
          skip_if_firefox('Known issue CNVS-24622')
          start_and_exit_quiz do
            expect_new_page_load { fj('a.ig-title', '#assignment-quizzes').click }
            expect_new_page_load { fln('Resume Quiz').click }
            verify_access_code_prompt
          end
        end

        it 'prompts for an access code upon resuming the quiz via the browser back button', priority: "1", test_id: 421222 do
          skip_if_firefox('Known issue CNVS-24622')
          start_and_exit_quiz do
            expect_new_page_load { driver.navigate.back }
            verify_access_code_prompt
          end
        end
      end
    end
  end
end
